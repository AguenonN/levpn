package main

import (
	"fmt"
	"log"
	"net"

	"github.com/gorilla/websocket"
)

func main() {
	listener, err := net.Listen("tcp", "localhost:1080")
	if err != nil {
		log.Fatal("listen error:", err)
	}
	defer listener.Close()

	log.Println("SOCKS5 proxy listening on localhost:1080")

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println("accept error:", err)
			continue
		}
		go handleConnection(conn)
	}
}

func handleConnection(conn net.Conn) {
	defer conn.Close()

	buf := make([]byte, 256)
	_, err := conn.Read(buf)
	if err != nil {
		log.Println("read error:", err)
		return
	}

	if buf[0] != 0x05 {
		log.Println("not SOCKS5")
		return
	}

	conn.Write([]byte{0x05, 0x00})

	_, err = conn.Read(buf)
	if err != nil {
		log.Println("read error:", err)
		return
	}

	addrType := buf[3]
	var dest string

	switch addrType {
	case 0x01: // IPv4
		ip := net.IP(buf[4:8])
		port := int(buf[8])<<8 | int(buf[9])
		dest = fmt.Sprintf("%s:%d", ip.String(), port)

	case 0x03: // nom de domaine
		addrLen := int(buf[4])
		host := string(buf[5 : 5+addrLen])
		port := int(buf[5+addrLen])<<8 | int(buf[5+addrLen+1])
		dest = fmt.Sprintf("%s:%d", host, port)

	default:
		log.Println("unsupported address type:", addrType)
		return
	}

	log.Println("destination:", dest)

	ws, _, err := websocket.DefaultDialer.Dial("ws://98.94.249.238:8080/tunnel", nil)
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
