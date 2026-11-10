package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	ratelimiter "github.com/dash-xd/ratelimiter"
	lifecycle "github.com/dash-xd/ratelimiter/profile/lifecycle"
	"github.com/redis/go-redis/v9"
)

func secret(path string) (string, error) {
	b, e := os.ReadFile(path)
	return strings.TrimSpace(string(b)), e
}
func bootstrapProfile() ratelimiter.Profile {
	return lifecycle.New(ratelimiter.TargetResolverFunc(func(ratelimiter.Input, ratelimiter.Stage) []ratelimiter.Target { return nil }))
}

func execute() error {
	if len(os.Args) != 3 {
		return errors.New("mode and scope required")
	}
	mode, scope := os.Args[1], os.Args[2]
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	if mode == "security-logma" || mode == "security-skymill" {
		role := strings.TrimPrefix(mode, "security-")
		pass, e := secret("/run/credentials/redis")
		if e != nil {
			return e
		}
		client := redis.NewClient(&redis.Options{Network: "unix", Addr: "/run/redis/redis.sock", Username: role, Password: pass, Protocol: 2, DialTimeout: 10 * time.Second, ReadTimeout: 10 * time.Second})
		defer client.Close()
		if e := client.Ping(ctx).Err(); e != nil {
			return e
		}
		cross := []any{"GET", scope + ":logma:lifecycle:qualification"}
		if role == "logma" {
			cross = []any{"HGETALL", scope + ":skymill:stream:github.webhooks"}
		}
		for _, command := range [][]any{{"ACL", "LIST"}, {"FUNCTION", "LIST"}, {"GET", "foreign:key"}, cross} {
			e := client.Do(ctx, command...).Err()
			if e == nil || !strings.HasPrefix(e.Error(), "NOPERM") {
				return fmt.Errorf("role %s escaped command/key boundary", role)
			}
		}
		fmt.Println("FATLINE_SERVICE_ACL=passed role=" + role)
		return nil
	}
	if mode == "bootstrap" {
		pass, e := secret("/run/credentials/redis")
		if e != nil {
			return e
		}
		client := redis.NewClient(&redis.Options{Network: "unix", Addr: "/run/redis/redis.sock", Username: "bootstrap", Password: pass, Protocol: 2, DialTimeout: 10 * time.Second, ReadTimeout: 10 * time.Second})
		defer client.Close()
		store, e := ratelimiter.NewRedisStore(client, ratelimiter.RedisConfig{Keyspace: scope + ":logma:lifecycle"})
		if e != nil {
			return e
		}
		if e = store.Bootstrap(ctx, bootstrapProfile()); e != nil {
			return e
		}
		if e = client.Do(ctx, "ACL", "SETUSER", "bootstrap", "off").Err(); e != nil {
			return e
		}
		verify := redis.NewClient(client.Options())
		defer verify.Close()
		if e = verify.Ping(ctx).Err(); e == nil || !strings.Contains(e.Error(), "WRONGPASS") {
			return errors.New("bootstrap revocation not enforced")
		}
		fmt.Println("FATLINE_FUNCTIONS_BOOTSTRAP=passed identity=revoked")
		return nil
	}
	if mode != "qualify" {
		return errors.New("unknown mode")
	}
	client := &http.Client{Timeout: 30 * time.Second}
	request := func(method, url string, body any) (map[string]any, error) {
		var payload io.Reader
		if body != nil {
			b, e := json.Marshal(body)
			if e != nil {
				return nil, e
			}
			payload = bytes.NewReader(b)
		}
		req, e := http.NewRequestWithContext(ctx, method, url, payload)
		if e != nil {
			return nil, e
		}
		req.Header.Set("Content-Type", "application/json")
		response, e := client.Do(req)
		if e != nil {
			return nil, e
		}
		defer response.Body.Close()
		data, e := io.ReadAll(io.LimitReader(response.Body, 1<<20))
		if e != nil {
			return nil, e
		}
		if response.StatusCode != 200 {
			return nil, fmt.Errorf("HTTP status %d: %s", response.StatusCode, string(data))
		}
		var result map[string]any
		e = json.Unmarshal(data, &result)
		return result, e
	}
	var readyErr error
	for {
		_, readyErr = request("GET", "http://logma:8080/lifecycle/readyz", nil)
		if readyErr == nil {
			break
		}
		select {
		case <-ctx.Done():
			return fmt.Errorf("Logma readiness: %w", readyErr)
		case <-time.After(time.Second):
		}
	}
	fmt.Println("FATLINE_LOGMA_STRICT_READINESS=passed")
	nonce := make([]byte, 24)
	if _, e := rand.Read(nonce); e != nil {
		return e
	}
	id := hex.EncodeToString(nonce)
	encoded := base64.StdEncoding.EncodeToString([]byte(id))
	msg := map[string]any{"idempotency_key": id, "message_id": id, "payload_base64": encoded}
	var first map[string]any
	var err error
	for {
		first, err = request("POST", "http://skymill:8081/v1/messages", msg)
		if err == nil {
			break
		}
		select {
		case <-ctx.Done():
			return err
		case <-time.After(time.Second):
		}
	}
	second, err := request("POST", "http://skymill:8081/v1/messages", msg)
	if err != nil {
		return err
	}
	if first["duplicate"] != false || second["duplicate"] != true || first["stream_entry_id"] != second["stream_entry_id"] {
		return errors.New("Skymill idempotency mismatch")
	}
	deliveries, err := request("POST", "http://skymill:8081/v1/deliveries/receive", map[string]int{"limit": 1})
	if err != nil {
		return err
	}
	entries, ok := deliveries["deliveries"].([]any)
	if !ok || len(entries) != 1 {
		return errors.New("missing Skymill delivery")
	}
	delivery := entries[0].(map[string]any)
	message := delivery["message"].(map[string]any)
	if message["id"] != id || message["payload_base64"] != encoded {
		return errors.New("Skymill delivery identity mismatch")
	}
	ack, err := request("POST", "http://skymill:8081/v1/deliveries/ack", map[string]any{"token": delivery["token"]})
	if err != nil {
		return err
	}
	if ack["ok"] != true {
		return errors.New("Skymill ack failed")
	}
	fmt.Println("FATLINE_SKYMILL_ROUNDTRIP=passed idempotency=passed ack=passed")
	return nil
}
func main() {
	if err := execute(); err != nil {
		fmt.Fprintln(os.Stderr, "Fatline services probe:", err)
		os.Exit(1)
	}
}
