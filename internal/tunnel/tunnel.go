package tunnel

import (
	"encoding/base64"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
)

func Handler(w http.ResponseWriter, r *http.Request) {
	expected := os.Getenv("LEVPN_PASSWORD")
	if expected == "" {
		log.Println("LEVPN_PASSWORD non defini")
		http.Error(w, "Server error", 500)
		return
	}

	auth := r.Header.Get("Proxy-Authorization")
	if auth == "" {
		w.Header().Set("Proxy-Authenticate", "Basic realm=\"levpn\"")
		w.WriteHeader(407)
		return
	}

	if !checkAuth(auth, expected) {
		log.Println("auth failed")
		w.Header().Set("Proxy-Authenticate", "Basic realm=\"levpn\"")
		w.WriteHeader(407)
		return
	}

	if r.Method == "CONNECT" {
		handleConnect(w, r)
		return
	}

	http.Error(w, "Method not allowed", 405)
}

func handleConnect(w http.ResponseWriter, r *http.Request) {
	dest := r.Host
	log.Println("tunneling ->", dest)

	tcp, err := net.Dial("tcp", dest)
	if err != nil {
		log.Println("dial error:", err)
		http.Error(w, "Bad gateway", 502)
		return
	}
	defer tcp.Close()

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "Hijack not supported", 500)
		return
	}

	conn, _, err := hj.Hijack()
	if err != nil {
		log.Println("hijack error:", err)
		return
	}
	defer conn.Close()

	conn.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n"))

	go func() { io.Copy(tcp, conn) }()
	io.Copy(conn, tcp)
}

func checkAuth(header string, expected string) bool {
	if !strings.HasPrefix(header, "Basic ") {
		return false
	}
	decoded, err := base64.StdEncoding.DecodeString(header[6:])
	if err != nil {
		return false
	}
	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return false
	}
	return parts[1] == expected
}
