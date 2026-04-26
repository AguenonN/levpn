package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"

	"github.com/gorilla/websocket"
)

var defaultRegion = "us"
var defaultToken = ""

var endpoints = map[string]string{
	"us":   "wss://us.aguenonnvpn.com/tunnel",
	"eu":   "wss://eu.aguenonnvpn.com/tunnel",
	"asia": "wss://asia.aguenonnvpn.com/tunnel",
	"sa":   "wss://sa.aguenonnvpn.com/tunnel",
}

func main() {
	port := flag.String("p", "1080", "Port local SOCKS5")
	flag.Parse()

	endpoint, ok := endpoints[defaultRegion]
	if !ok {
		log.Fatalf("Region invalide : %s", defaultRegion)
	}

	if defaultToken == "" {
		log.Fatal("Token non défini — binaire mal compilé")
	}

	log.Printf("levpn → région %s (%s)", defaultRegion, endpoint)

	localAddr := net.JoinHostPort("127.0.0.1", *port)
	listener, err := net.Listen("tcp", localAddr)
	if err != nil {
		log.Fatalf("Port %s déjà utilisé. Relance avec -p 1081", *port)
	}
	defer listener.Close()

	log.Printf("SOCKS5 proxy listening on %s", localAddr)

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println("accept error:", err)
			continue
		}
		go handleConnection(conn, endpoint)
	}
}

func handleConnection(conn net.Conn, endpoint string) {
	defer conn.Close()

	buf := make([]byte, 256)
	_, err := conn.Read(buf)
	if err != nil {
		return
	}

	if buf[0] != 0x05 {
		return
	}

	conn.Write([]byte{0x05, 0x00})

	_, err = conn.Read(buf)
	if err != nil {
		return
	}

	addrType := buf[3]
	var dest string

	switch addrType {
	case 0x01:
		ip := net.IP(buf[4:8])
		port := int(buf[8])<<8 | int(buf[9])
		dest = fmt.Sprintf("%s:%d", ip.String(), port)
	case 0x03:
		addrLen := int(buf[4])
		host := string(buf[5 : 5+addrLen])
		port := int(buf[5+addrLen])<<8 | int(buf[5+addrLen+1])
		dest = fmt.Sprintf("%s:%d", host, port)
	default:
		return
	}

	log.Println("destination:", dest)

	// Header avec JWT
	header := http.Header{}
	header.Add("Authorization", "Bearer "+defaultToken)

	ws, _, err := websocket.DefaultDialer.Dial(endpoint, header)
	if err != nil {
		log.Println("websocket error:", err)
		return
	}
	defer ws.Close()

	ws.WriteMessage(websocket.TextMessage, []byte(dest))

	conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00})

	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := conn.Read(buf)
			if n > 0 {
				ws.WriteMessage(websocket.BinaryMessage, buf[:n])
			}
			if err != nil {
				return
			}
		}
	}()

	for {
		_, msg, err := ws.ReadMessage()
		if err != nil {
			return
		}
		conn.Write(msg)
	}
}
