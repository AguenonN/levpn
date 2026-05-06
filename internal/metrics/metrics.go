package metrics

import (
	"encoding/json"
	"io"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

var (
	ActiveConns   atomic.Int64
	TotalConns    atomic.Int64
	TotalBytesIn  atomic.Int64
	TotalBytesOut atomic.Int64
	AuthFailures  atomic.Int64
	StartTime     = time.Now()

	connLog = make([]ConnEntry, 0, maxLogSize)
	connMu  sync.Mutex
)

const maxLogSize = 200

type ConnEntry struct {
	Timestamp   time.Time `json:"timestamp"`
	Destination string    `json:"destination"`
	BytesIn     int64     `json:"bytes_in"`
	BytesOut    int64     `json:"bytes_out"`
	DurationMs  int64     `json:"duration_ms"`
	Status      string    `json:"status"`
	ClientIP    string    `json:"client_ip"`
}

type Snapshot struct {
	Region        string      `json:"region"`
	Uptime        int64       `json:"uptime_seconds"`
	ActiveConns   int64       `json:"active_connections"`
	TotalConns    int64       `json:"total_connections"`
	TotalBytesIn  int64       `json:"total_bytes_in"`
	TotalBytesOut int64       `json:"total_bytes_out"`
	AuthFailures  int64       `json:"auth_failures"`
	RecentConns   []ConnEntry `json:"recent_connections"`
	Timestamp     time.Time   `json:"timestamp"`
}

func TrackConn() {
	ActiveConns.Add(1)
	TotalConns.Add(1)
}

func UntrackConn() {
	ActiveConns.Add(-1)
}

func LogConn(entry ConnEntry) {
	connMu.Lock()
	defer connMu.Unlock()
	if len(connLog) >= maxLogSize {
		copy(connLog, connLog[1:])
		connLog = connLog[:maxLogSize-1]
	}
	connLog = append(connLog, entry)
}

func LogAuthFailure() {
	AuthFailures.Add(1)
}

type CountingWriter struct {
	W     io.Writer
	Count int64
}

func (cw *CountingWriter) Write(p []byte) (int, error) {
	n, err := cw.W.Write(p)
	cw.Count += int64(n)
	TotalBytesOut.Add(int64(n))
	return n, err
}

type CountingReader struct {
	R     io.Reader
	Count int64
}

func (cr *CountingReader) Read(p []byte) (int, error) {
	n, err := cr.R.Read(p)
	cr.Count += int64(n)
	TotalBytesIn.Add(int64(n))
	return n, err
}

func Handler(region string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		connMu.Lock()
		recent := make([]ConnEntry, len(connLog))
		copy(recent, connLog)
		connMu.Unlock()

		for i, j := 0, len(recent)-1; i < j; i, j = i+1, j-1 {
			recent[i], recent[j] = recent[j], recent[i]
		}

		if len(recent) > 50 {
			recent = recent[:50]
		}

		snap := Snapshot{
			Region:        region,
			Uptime:        int64(time.Since(StartTime).Seconds()),
			ActiveConns:   ActiveConns.Load(),
			TotalConns:    TotalConns.Load(),
			TotalBytesIn:  TotalBytesIn.Load(),
			TotalBytesOut: TotalBytesOut.Load(),
			AuthFailures:  AuthFailures.Load(),
			RecentConns:   recent,
			Timestamp:     time.Now(),
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(snap)
	}
}
