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
