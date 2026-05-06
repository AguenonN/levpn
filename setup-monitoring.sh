#!/bin/bash
# ─── setup-monitoring.sh ─────────────────────────────────────────────────────
#
# Lance depuis ~/levpn :
#   chmod +x setup-monitoring.sh && ./setup-monitoring.sh
#
# Ce script :
#   1. Crée internal/metrics/metrics.go (compteurs atomiques + ring buffer)
#   2. Met à jour internal/tunnel/tunnel.go (instrumentation métriques)
#   3. Met à jour cmd/server/main.go (endpoint /metrics)
#   4. Recompile server-linux
#   5. Affiche les instructions de déploiement
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

if [ ! -d "cmd/server" ] || [ ! -d "internal/tunnel" ]; then
  echo "Erreur : lance ce script depuis ~/levpn"
  exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Setup monitoring levpn                             ║"
echo "╚══════════════════════════════════════════════════════╝"

# ── Créer le package metrics ─────────────────────────────────────────────────

mkdir -p internal/metrics

cat > internal/metrics/metrics.go << 'ENDOFFILE'
package metrics

import (
	"encoding/json"
	"io"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

var (
	ActiveConns   atomic.Int64
	TotalConns    atomic.Int64
	TotalBytesIn  atomic.Int64
	TotalBytesOut atomic.Int64
	AuthFailures  atomic.Int64
	StartTime     = time.Now()

	connLog = make([]ConnEntry, 0, maxLogSize)
	connMu  sync.Mutex
)

const maxLogSize = 200

type ConnEntry struct {
	Timestamp   time.Time `json:"timestamp"`
	Destination string    `json:"destination"`
	BytesIn     int64     `json:"bytes_in"`
	BytesOut    int64     `json:"bytes_out"`
	DurationMs  int64     `json:"duration_ms"`
	Status      string    `json:"status"`
	ClientIP    string    `json:"client_ip"`
}

type Snapshot struct {
	Region        string      `json:"region"`
	Uptime        int64       `json:"uptime_seconds"`
	ActiveConns   int64       `json:"active_connections"`
	TotalConns    int64       `json:"total_connections"`
	TotalBytesIn  int64       `json:"total_bytes_in"`
	TotalBytesOut int64       `json:"total_bytes_out"`
	AuthFailures  int64       `json:"auth_failures"`
	RecentConns   []ConnEntry `json:"recent_connections"`
	Timestamp     time.Time   `json:"timestamp"`
}

func TrackConn() {
	ActiveConns.Add(1)
	TotalConns.Add(1)
}

func UntrackConn() {
	ActiveConns.Add(-1)
}

func LogConn(entry ConnEntry) {
	connMu.Lock()
	defer connMu.Unlock()
	if len(connLog) >= maxLogSize {
		copy(connLog, connLog[1:])
		connLog = connLog[:maxLogSize-1]
	}
	connLog = append(connLog, entry)
}

func LogAuthFailure() {
	AuthFailures.Add(1)
}

type CountingWriter struct {
	W     io.Writer
	Count int64
}

func (cw *CountingWriter) Write(p []byte) (int, error) {
	n, err := cw.W.Write(p)
	cw.Count += int64(n)
	TotalBytesOut.Add(int64(n))
	return n, err
}

type CountingReader struct {
	R     io.Reader
	Count int64
}

func (cr *CountingReader) Read(p []byte) (int, error) {
	n, err := cr.R.Read(p)
	cr.Count += int64(n)
	TotalBytesIn.Add(int64(n))
	return n, err
}

func Handler(region string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		connMu.Lock()
		recent := make([]ConnEntry, len(connLog))
		copy(recent, connLog)
		connMu.Unlock()

		for i, j := 0, len(recent)-1; i < j; i, j = i+1, j-1 {
			recent[i], recent[j] = recent[j], recent[i]
		}

		if len(recent) > 50 {
			recent = recent[:50]
		}

		snap := Snapshot{
			Region:        region,
			Uptime:        int64(time.Since(StartTime).Seconds()),
			ActiveConns:   ActiveConns.Load(),
			TotalConns:    TotalConns.Load(),
			TotalBytesIn:  TotalBytesIn.Load(),
			TotalBytesOut: TotalBytesOut.Load(),
			AuthFailures:  AuthFailures.Load(),
			RecentConns:   recent,
			Timestamp:     time.Now(),
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(snap)
	}
}
ENDOFFILE

echo "✓ internal/metrics/metrics.go créé"

# ── Mettre à jour tunnel.go ──────────────────────────────────────────────────

cat > internal/tunnel/tunnel.go << 'ENDOFFILE'
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
ENDOFFILE

echo "✓ internal/tunnel/tunnel.go mis à jour (avec métriques)"

# ── Mettre à jour cmd/server/main.go ────────────────────────────────────────

cat > cmd/server/main.go << 'ENDOFFILE'
package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"

	"github.com/aguenonn/levpn/internal/metrics"
	"github.com/aguenonn/levpn/internal/tunnel"
)

type proxyHandler struct {
	metricsHandler http.HandlerFunc
}

func (p *proxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/metrics" && r.Method != http.MethodConnect {
		p.metricsHandler(w, r)
		return
	}

	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method == http.MethodConnect {
		tunnel.Handler(w, r)
		return
	}

	w.Write([]byte("OK"))
}

func main() {
	region := os.Getenv("LEVPN_REGION")
	if region == "" {
		region = "us"
	}

	handler := &proxyHandler{
		metricsHandler: metrics.Handler(region),
	}

	go func() {
		log.Printf("HTTP proxy listening on :8080 (region: %s)", region)
		if err := http.ListenAndServe(":8080", handler); err != nil {
			log.Printf("HTTP :8080 error: %v", err)
		}
	}()

	certFile, keyFile := getCertPaths()
	log.Printf("TLS certs: %s, %s", certFile, keyFile)

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Printf("TLS certs not found (%v) — port 8080 only", err)
		select {}
	}

	tlsConfig := &tls.Config{Certificates: []tls.Certificate{cert}}
	listener, err := tls.Listen("tcp", ":443", tlsConfig)
	if err != nil {
		log.Fatalf("TLS listen error: %v", err)
	}
	defer listener.Close()

	log.Println("HTTPS proxy listening on :443")

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("accept error: %v", err)
			continue
		}
		go handleTLSConn(conn, handler)
	}
}

func handleTLSConn(conn net.Conn, handler http.Handler) {
	defer conn.Close()
	http.Serve(&singleConnListener{conn: conn}, handler)
}

type singleConnListener struct {
	conn   net.Conn
	served bool
}

func (l *singleConnListener) Accept() (net.Conn, error) {
	if l.served {
		return nil, fmt.Errorf("done")
	}
	l.served = true
	return l.conn, nil
}

func (l *singleConnListener) Close() error   { return nil }
func (l *singleConnListener) Addr() net.Addr { return l.conn.LocalAddr() }

func getCertPaths() (string, string) {
	certFile := os.Getenv("LEVPN_CERT_FILE")
	keyFile := os.Getenv("LEVPN_KEY_FILE")
	if certFile != "" && keyFile != "" {
		return certFile, keyFile
	}

	region := os.Getenv("LEVPN_REGION")
	if region == "" {
		region = "us"
	}
	domain := region + ".aguenonnvpn.com"
	return fmt.Sprintf("/etc/letsencrypt/live/%s/fullchain.pem", domain),
		fmt.Sprintf("/etc/letsencrypt/live/%s/privkey.pem", domain)
}
ENDOFFILE

echo "✓ cmd/server/main.go mis à jour (endpoint /metrics)"

# ── Compiler ─────────────────────────────────────────────────────────────────

echo ""
echo "→ Compilation server-linux..."
GOOS=linux GOARCH=amd64 go build -o server-linux ./cmd/server/
echo "✓ server-linux compilé"

# ── Résumé ───────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  Monitoring installé. Prochaines étapes :"
echo ""
echo "  1. Déployer sur les servers actifs :"
echo "     ./scripts/deploy-server.sh"
echo ""
echo "  2. Tester l'endpoint metrics :"
echo "     curl http://us.aguenonnvpn.com:8080/metrics | python3 -m json.tool"
echo ""
echo "  3. Le dashboard React est dans tes Downloads"
echo "     (levpn-dashboard.jsx)"
echo "══════════════════════════════════════════════════════════"
