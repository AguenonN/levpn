package tunnel

import (
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"

	"github.com/golang-jwt/jwt/v5"
)

func HandleSOCKS5(conn net.Conn) {
	defer conn.Close()

	buf := make([]byte, 256)

	_, err := conn.Read(buf)
	if err != nil || buf[0] != 0x05 {
		return
	}

	nMethods := int(buf[1])
	methods := buf[2 : 2+nMethods]

	hasAuth := false
	hasNoAuth := false
	for _, m := range methods {
		if m == 0x02 {
			hasAuth = true
		}
		if m == 0x00 {
			hasNoAuth = true
		}
	}

	if hasAuth {
		conn.Write([]byte{0x05, 0x02})
		_, err = conn.Read(buf)
		if err != nil {
			return
		}
		uLen := int(buf[1])
		username := string(buf[2 : 2+uLen])
		pLen := int(buf[2+uLen])
		password := string(buf[3+uLen : 3+uLen+pLen])
		log.Printf("auth attempt: user=%s", username)
		if !validateJWT(password) {
			conn.Write([]byte{0x01, 0x01})
			log.Println("connexion refusee : token invalide")
			return
		}
		conn.Write([]byte{0x01, 0x00})
	} else if hasNoAuth {
		conn.Write([]byte{0x05, 0x00})
		log.Println("connexion sans auth (extension)")
	} else {
		conn.Write([]byte{0x05, 0xFF})
		return
	}

	_, err = conn.Read(buf)
	if err != nil || buf[0] != 0x05 || buf[1] != 0x01 {
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
		conn.Write([]byte{0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	log.Println("tunneling ->", dest)

	tcp, err := net.Dial("tcp", dest)
	if err != nil {
		conn.Write([]byte{0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}
	defer tcp.Close()

	conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0})

	go func() {
		io.Copy(tcp, conn)
	}()
	io.Copy(conn, tcp)
}

func validateJWT(tokenString string) bool {
	secret := []byte(os.Getenv("LEVPN_SECRET"))
	if len(secret) == 0 {
		log.Println("LEVPN_SECRET non defini")
		return false
	}
	tokenString = strings.TrimPrefix(tokenString, "Bearer ")
	token, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		return secret, nil
	})
	return err == nil && token.Valid
}
