package tunnel

import (
	"encoding/base64"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aguenonn/levpn/internal/metrics"
)

func Handler(w http.ResponseWriter, r *http.Request) {
	password := os.Getenv("LEVPN_PASSWORD")
	clientIP := r.RemoteAddr

	authHeader := r.Header.Get("Proxy-Authorization")
	if authHeader == "" {
		metrics.LogAuthFailure()
		w.Header().Set("Proxy-Authenticate", `Basic realm="levpn"`)
		http.Error(w, "Proxy Authentication Required", http.StatusProxyAuthRequired)
		return
	}

	if !checkAuth(authHeader, password) {
		metrics.LogAuthFailure()
		log.Printf("auth failed from %s", clientIP)
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

func handleConnect(w http.ResponseWriter, r *http.Request, clientIP string) {
	dest := r.Host
	start := time.Now()

	metrics.TrackConn()
	defer metrics.UntrackConn()

	tcp, err := net.DialTimeout("tcp", dest, 10*time.Second)
	if err != nil {
		log.Printf("dial error → %s: %v", dest, err)
		metrics.LogConn(metrics.ConnEntry{
			Timestamp:  start,
			Destination: dest,
			Status:     "error",
			DurationMs: time.Since(start).Milliseconds(),
			ClientIP:   clientIP,
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

	log.Printf("tunneling %s → %s", clientIP, dest)

	cw := &metrics.CountingWriter{W: tcp}
	cr := &metrics.CountingReader{R: tcp}

	done := make(chan struct{}, 2)

	go func() {
		io.Copy(cw, clientConn)
		done <- struct{}{}
	}()

	go func() {
		io.Copy(clientConn, cr)
		done <- struct{}{}
	}()

	<-done

	duration := time.Since(start)

	metrics.LogConn(metrics.ConnEntry{
		Timestamp:   start,
		Destination: dest,
		BytesIn:     cr.Count,
		BytesOut:    cw.Count,
		DurationMs:  duration.Milliseconds(),
		Status:      "closed",
		ClientIP:    clientIP,
	})
}

func checkAuth(header, expectedPassword string) bool {
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

	return creds[1] == expectedPassword
}
