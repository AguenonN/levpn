package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/aguenonn/levpn/internal/metrics"
	"github.com/aguenonn/levpn/internal/tunnel"
)

type proxyHandler struct {
	metricsHandler http.HandlerFunc
	password       string
}

func (p *proxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// 1. Preflight CORS d'abord : il n'embarque jamais d'identifiants.
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.WriteHeader(http.StatusOK)
		return
	}

	// 2. /metrics : accès direct (pas via proxy) → header Authorization.
	if r.URL.Path == "/metrics" && r.Method != http.MethodConnect {
		if !tunnel.ValidBasic(r.Header.Get("Authorization"), p.password) {
			// Pas de WWW-Authenticate : évite la popup native du navigateur côté dashboard.
			w.Header().Set("Access-Control-Allow-Origin", "*")
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		p.metricsHandler(w, r)
		return
	}

	// 3. Proxy.
	if r.Method == http.MethodConnect {
		tunnel.Handler(w, r)
		return
	}

	// Requête forward-proxy (URL absolue) = site http:// en clair : non supporté.
	if r.URL.IsAbs() {
		http.Error(w, "levpn: HTTPS-only proxy, plain http:// sites are not supported", http.StatusMethodNotAllowed)
		return
	}
	w.Write([]byte("OK"))
}

func main() {
	password := os.Getenv("LEVPN_PASSWORD")
	if password == "" {
		log.Fatal("LEVPN_PASSWORD is empty — refusing to start an open proxy")
	}

	region := os.Getenv("LEVPN_REGION")
	if region == "" {
		region = "us"
	}

	handler := &proxyHandler{
		metricsHandler: metrics.Handler(region),
		password:       password,
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

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		NextProtos:   []string{"http/1.1"},
	}
	listener, err := tls.Listen("tcp", ":443", tlsConfig)
	if err != nil {
		log.Fatalf("TLS listen error: %v", err)
	}

	srv := &http.Server{
		Handler: handler,
		// Map non-nil vide = HTTP/2 désactivé. CONNECT exige Hijack(), HTTP/1.1 uniquement.
		TLSNextProto: map[string]func(*http.Server, *tls.Conn, http.Handler){},
	}

	log.Println("HTTPS proxy listening on :443")
	log.Fatal(srv.Serve(listener))
}

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
