package main

import (
	"context"
	"encoding/json"
	"github.com/xd-dash/logma/internal/pubsubmodel"
	"testing"
)

func TestResourcePublisherBindsMetadataAndEmitsOnce(t *testing.T) {
	input := resourceInput{Channel: "scope:qualification", PublisherID: "nix-xd-dispatch-one", Payload: "unique-payload"}
	sent := 0
	producer := &resourcePublisher{input: input, emit: func(_ context.Context, channel, payload string) error {
		if channel != input.Channel || payload != input.Payload {
			t.Fatal("dispatch binding changed")
		}
		sent++
		return nil
	}}
	config, _ := json.Marshal(resourceConfig{Payload: input.Payload})
	publisher := pubsubmodel.Publisher{ID: input.PublisherID, Channel: input.Channel, Type: "nix-xd-once", Config: config}
	channel := pubsubmodel.Channel{Name: input.Channel}
	for i := 0; i < 2; i++ {
		if err := producer.EnsureActive(context.Background(), publisher, channel); err != nil {
			t.Fatal(err)
		}
	}
	if sent != 1 {
		t.Fatal("producer emitted twice")
	}
	publisher.Channel = "foreign:channel"
	if err := producer.EnsureActive(context.Background(), publisher, channel); err == nil {
		t.Fatal("accepted changed resource")
	}
	if sent != 1 {
		t.Fatal("invalid resource emitted")
	}
}
