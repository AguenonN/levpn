package tunnel

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aguenonn/levpn/internal/metrics"
)

// Ports de destination autorisés : web uniquement.
var allowedPorts = map[string]bool{"443": true, "80": true}

// 100.64.0.0/10 (CGNAT) n'est pas couvert par net.IP.IsPrivate.
var cgnat = &net.IPNet{IP: net.IPv4(100, 64, 0, 0), Mask: net.CIDRMask(10, 32)}

func Handler(w http.ResponseWriter, r *http.Request) {
	clientIP := r.RemoteAddr
	authHeader := r.Header.Get("Proxy-Authorization")

	if !ValidBasic(authHeader, os.Getenv("LEVPN_PASSWORD")) {
		metrics.LogAuthFailure()
		if authHeader != "" {
			log.Printf("auth failed from %s", clientIP)
		}
		w.Header().Set("Proxy-Authenticate", `Basic realm="levpn"`)
		http.Error(w, "Proxy Authentication Required", http.StatusProxyAuthRequired)
		return
	}

	if r.Method != http.MethodConnect {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	handleConnect(w, r, clientIP)
}

// ValidBasic vérifie un header "Basic base64(user:pass)". Le nom d'utilisateur est ignoré.
// Un mot de passe attendu vide est toujours refusé.
func ValidBasic(header, expected string) bool {
	if expected == "" {
		return false
	}
	parts := strings.SplitN(header, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Basic") {
		return false
	}
	decoded, err := base64.StdEncoding.DecodeString(parts[1])
	if err != nil {
		return false
	}
	creds := strings.SplitN(string(decoded), ":", 2)
	if len(creds) != 2 {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(creds[1]), []byte(expected)) == 1
}

func blocked(ip net.IP) bool {
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
		ip.IsLinkLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() ||
		cgnat.Contains(ip)
}

// resolveAllowed valide port + IPs et renvoie "ip:port" à dialer (anti DNS rebinding).
func resolveAllowed(ctx context.Context, hostport string) (string, error) {
	host, port, err := net.SplitHostPort(hostport)
	if err != nil {
		return "", fmt.Errorf("invalid destination %q", hostport)
	}
	if !allowedPorts[port] {
		return "", fmt.Errorf("port %s not allowed", port)
	}
	addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil || len(addrs) == 0 {
		return "", fmt.Errorf("resolve %s: %v", host, err)
	}
	var chosen net.IP
	for _, a := range addrs {
		if blocked(a.IP) {
			return "", fmt.Errorf("%s resolves to blocked address %s", host, a.IP)
		}
		// Préférer IPv4 : les nœuds EC2 n'ont pas d'IPv6 sortant.
		if chosen == nil || (chosen.To4() == nil && a.IP.To4() != nil) {
			chosen = a.IP
		}
	}
	return net.JoinHostPort(chosen.String(), port), nil
}

func handleConnect(w http.ResponseWriter, r *http.Request, clientIP string) {
	dest := r.Host
	start := time.Now()

	metrics.TrackConn()
	defer metrics.UntrackConn()

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	target, err := resolveAllowed(ctx, dest)
	if err != nil {
		log.Printf("blocked %s → %s: %v", clientIP, dest, err)
		metrics.LogConn(metrics.ConnEntry{
			Timestamp:   start,
			Destination: dest,
			Status:      "blocked",
			DurationMs:  time.Since(start).Milliseconds(),
			ClientIP:    clientIP,
		})
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	tcp, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		log.Printf("dial error → %s (%s): %v", dest, target, err)
		metrics.LogConn(metrics.ConnEntry{
			Timestamp:   start,
			Destination: dest,
			Status:      "error",
			DurationMs:  time.Since(start).Milliseconds(),
			ClientIP:    clientIP,
		})
		http.Error(w, "Bad Gateway", http.StatusBadGateway)
		return
	}
	defer tcp.Close()

	hijacker, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	clientConn, _, err := hijacker.Hijack()
	if err != nil {
		log.Printf("hijack error: %v", err)
		return
	}
	defer clientConn.Close()

	clientConn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))
	log.Printf("tunneling %s → %s (%s)", clientIP, dest, target)

	cw := &metrics.CountingWriter{W: tcp}
	cr := &metrics.CountingReader{R: tcp}
	done := make(chan struct{}, 2)

	go func() { io.Copy(cw, clientConn); done <- struct{}{} }()
	go func() { io.Copy(clientConn, cr); done <- struct{}{} }()
	<-done

	metrics.LogConn(metrics.ConnEntry{
		Timestamp:   start,
		Destination: dest,
		BytesIn:     cr.Count,
		BytesOut:    cw.Count,
		DurationMs:  time.Since(start).Milliseconds(),
		Status:      "closed",
		ClientIP:    clientIP,
	})
}
