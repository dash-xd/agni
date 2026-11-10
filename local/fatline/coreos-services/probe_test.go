package main

import (
	ratelimiter "github.com/dash-xd/ratelimiter"
	lifecycle "github.com/dash-xd/ratelimiter/profile/lifecycle"
	"github.com/redis/go-redis/v9"
	"testing"
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
