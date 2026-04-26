package tunnel

import (
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func Handler(w http.ResponseWriter, r *http.Request) {
	// Auth JWT
	secretKey := []byte(os.Getenv("LEVPN_SECRET"))
	if len(secretKey) == 0 {
		log.Println("LEVPN_SECRET non défini")
		http.Error(w, "Server misconfigured", http.StatusInternalServerError)
		return
	}

	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") {
		log.Println("connexion refusée : pas de token")
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	tokenString := strings.TrimPrefix(authHeader, "Bearer ")
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		return secretKey, nil
	})

	if err != nil || !token.Valid {
		log.Println("connexion refusée : token invalide")
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Upgrade HTTP → WebSocket
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("upgrade error:", err)
		return
	}
	defer ws.Close()

	// Lire la destination
	_, dest, err := ws.ReadMessage()
	if err != nil {
		log.Println("read dest error:", err)
		return
	}

	// Connexion TCP vers la destination
	tcp, err := net.Dial("tcp", string(dest))
	if err != nil {
		log.Println("dial error:", err)
		return
	}
	defer tcp.Close()

	log.Printf("tunneling → %s", string(dest))

	// Pipe bidirectionnel WebSocket ↔ TCP
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
