package main

import (
	"crypto/tls"
	"log"
	"net/http"
	"os"

	"github.com/aguenonn/levpn/internal/tunnel"
)

type proxyHandler struct{}

func (p *proxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodConnect {
		tunnel.Handler(w, r)
		return
	}
	w.Write([]byte("OK"))
}

func main() {
	log.Println("levpn server starting...")

	handler := &proxyHandler{}

	// Plain HTTP on 8080 for browsers via PAC
	go func() {
		log.Println("HTTP CONNECT proxy (plain) on :8080")
		log.Fatal(http.ListenAndServe(":8080", handler))
	}()

	// TLS on 443 for curl and advanced clients
	region := os.Getenv("LEVPN_REGION")
	certDir := "/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/" + region + ".aguenonnvpn.com/"
	certFile := certDir + region + ".aguenonnvpn.com.crt"
	keyFile := certDir + region + ".aguenonnvpn.com.key"

	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		log.Printf("TLS error: %v, running plain HTTP only on :8080", err)
		select {}
	}

	tlsConfig := &tls.Config{Certificates: []tls.Certificate{cert}}
	server := &http.Server{Addr: ":443", Handler: handler, TLSConfig: tlsConfig}
	log.Println("HTTP CONNECT proxy (TLS) on :443")
	log.Fatal(server.ListenAndServeTLS("", ""))
}
