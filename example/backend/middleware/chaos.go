// Package middleware holds the lab's request accounting and fault injection.
package middleware

import (
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// Chaos modes applied to matching requests.
const (
	ModeNone    = "none"
	ModeLatency = "latency" // sleep LatencyMs, then serve normally
	ModeFail503 = "fail503" // respond 503 immediately
	ModeHang    = "hang"    // never respond (until the client gives up)
	ModeDrop    = "drop"    // close the TCP connection without a response
)

// ChaosConfig selects the fault applied to requests whose path starts with
// Match (empty Match = every /api/ path except /api/lab).
type ChaosConfig struct {
	Mode      string `json:"mode"`
	LatencyMs int    `json:"latencyMs"`
	Match     string `json:"match"`
}

// Lab keeps the chaos config and per-route request counters.
type Lab struct {
	mu     sync.Mutex
	chaos  ChaosConfig
	counts map[string]int
	since  time.Time
}

// NewLab returns a Lab with chaos disabled.
func NewLab() *Lab {
	return &Lab{chaos: ChaosConfig{Mode: ModeNone}, counts: map[string]int{}, since: time.Now()}
}

// SetChaos replaces the active chaos config.
func (l *Lab) SetChaos(c ChaosConfig) {
	if c.Mode == "" {
		c.Mode = ModeNone
	}
	l.mu.Lock()
	l.chaos = c
	l.mu.Unlock()
}

// Chaos returns the active chaos config.
func (l *Lab) Chaos() ChaosConfig {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.chaos
}

// Stats returns a sorted snapshot of the request counters.
func (l *Lab) Stats() map[string]any {
	l.mu.Lock()
	defer l.mu.Unlock()
	keys := make([]string, 0, len(l.counts))
	total := 0
	for k, v := range l.counts {
		keys = append(keys, k)
		total += v
	}
	sort.Strings(keys)
	ordered := make([]map[string]any, 0, len(keys))
	for _, k := range keys {
		ordered = append(ordered, map[string]any{"route": k, "count": l.counts[k]})
	}
	return map[string]any{
		"since":    l.since.UTC().Format(time.RFC3339),
		"seconds":  time.Since(l.since).Seconds(),
		"total":    total,
		"requests": ordered,
	}
}

// ResetStats clears the request counters.
func (l *Lab) ResetStats() {
	l.mu.Lock()
	l.counts = map[string]int{}
	l.since = time.Now()
	l.mu.Unlock()
}

func (l *Lab) count(key string) {
	l.mu.Lock()
	l.counts[key]++
	l.mu.Unlock()
}

// routeKey keeps the collection and file names (to count per-file
// downloads) but strips query strings.
func routeKey(r *http.Request) string {
	return r.Method + " " + r.URL.Path
}

// Handler counts every non-lab API request and applies the chaos config.
func (l *Lab) Handler(e *core.RequestEvent) error {
	path := e.Request.URL.Path
	if !strings.HasPrefix(path, "/api/") || strings.HasPrefix(path, "/api/lab") {
		return e.Next()
	}
	l.count(routeKey(e.Request))

	c := l.Chaos()
	if c.Mode == ModeNone || (c.Match != "" && !strings.HasPrefix(path, c.Match)) {
		return e.Next()
	}

	switch c.Mode {
	case ModeLatency:
		select {
		case <-time.After(time.Duration(c.LatencyMs) * time.Millisecond):
		case <-e.Request.Context().Done():
			return nil
		}
		return e.Next()
	case ModeFail503:
		return e.JSON(http.StatusServiceUnavailable, map[string]any{
			"status": 503, "message": "lab chaos: service unavailable", "data": map[string]any{},
		})
	case ModeHang:
		select {
		case <-e.Request.Context().Done():
		case <-time.After(10 * time.Minute):
		}
		return nil
	case ModeDrop:
		conn, _, err := http.NewResponseController(e.Response).Hijack()
		if err != nil {
			return e.InternalServerError("lab chaos: hijack failed", err)
		}
		return conn.Close()
	}
	return e.Next()
}
