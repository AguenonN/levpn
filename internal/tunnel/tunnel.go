package tunnel

import (
	"io"
	"log"
	"net"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func Handler(w http.ResponseWriter, r *http.Request) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("upgrade error:", err)
		return
	}
	defer ws.Close()

	_, dest, err := ws.ReadMessage()
	if err != nil {
		log.Println("read dest error:", err)
		return
	}

	tcp, err := net.Dial("tcp", string(dest))
	if err != nil {
		log.Println("dial error:", err)
		return
	}
	defer tcp.Close()

	log.Printf("tunneling → %s", string(dest))

	go func() {
		for {
			_, msg, err := ws.ReadMessage()
			if err != nil {
				return
			}
			_, err = tcp.Write(msg)
			if err != nil {
				return
			}
		}
	}()

	buf := make([]byte, 32*1024)
	for {
		n, err := tcp.Read(buf)
		if n > 0 {
			ws.WriteMessage(websocket.BinaryMessage, buf[:n])
		}
		if err == io.EOF || err != nil {
			return
		}
	}
}
