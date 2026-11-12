package main

import (
	ratelimiter "github.com/dash-xd/ratelimiter"
	lifecycle "github.com/dash-xd/ratelimiter/profile/lifecycle"
	"github.com/redis/go-redis/v9"
	"testing"
	"net/http"
)

func TestBootstrapProfileSatisfiesLifecycleContract(t *testing.T) {
	client := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1"})
	defer client.Close()
	store, err := ratelimiter.NewRedisStore(client, ratelimiter.RedisConfig{Keyspace: "qualification:logma:lifecycle"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Limiter(lifecycle.New(nil)); err == nil {
		t.Fatal("expected invalid control profile")
	}
	if _, err := store.Limiter(bootstrapProfile()); err != nil {
		t.Fatalf("bootstrap profile rejected: %v", err)
	}
}

func TestReadinessUsesLogmaPlainTextContract(t *testing.T) {
	for _, test := range []struct {
		status            int
		contentType, body string
		valid             bool
	}{
		{200, "text/plain; charset=utf-8", "ready\n", true},
		{503, "text/plain", "not ready\n", false},
		{200, "text/plain", "not ready\n", false},
		{200, "application/json", "{}", false},
	} {
		err := readinessResponse(test.status, test.contentType, []byte(test.body))
		if (err == nil) != test.valid {
			t.Fatalf("status=%d body=%q: %v", test.status, test.body, err)
		}
	}
}

func TestLogmaReadinessPlainTextContract(t *testing.T) {
	if err := validateReadiness(http.StatusOK, []byte("ready\\n")); err != nil {
		t.Fatal(err)
	}
	for _, item := range []struct {
		status int
		body string
	}{
		{http.StatusServiceUnavailable, "not ready\\n"},
		{http.StatusOK, "ready"},
		{http.StatusOK, "{\\\"ready\\\":true}"},
	} {
		if err := validateReadiness(item.status, []byte(item.body)); err == nil {
			t.Errorf("accepted invalid readiness status=%d body=%q", item.status, item.body)
		}
	}
}
