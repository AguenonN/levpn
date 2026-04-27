package main

import (
	"log"
	"net"
	"github.com/aguenonn/levpn/internal/tunnel"
)

func main() {
	log.Println("levpn server starting...")

	listener, err := net.Listen("tcp", ":1080")
	if err != nil {
		log.Fatal(err)
	}
	defer listener.Close()

	log.Println("SOCKS5 plain listening on :1080")

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println("accept error:", err)
			continue
		}
		go tunnel.HandleSOCKS5(conn)
	}
}
