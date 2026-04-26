package main

import (
	"log"
	"net/http"

	"github.com/aguenonn/levpn/internal/tunnel"
)

func main() {
	http.HandleFunc("/tunnel", tunnel.Handler)

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("OK"))
	})

	log.Println("server listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
