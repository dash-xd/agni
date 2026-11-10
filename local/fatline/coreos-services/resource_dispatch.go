package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/xd-dash/logma/internal/pubsubmodel"
	"github.com/xd-dash/logma/internal/pubsubruntime"
)

type resourceInput struct{ Channel, PublisherID, Payload string }
type resourceConfig struct {
	Payload string `json:"payload"`
}

// This finite producer is a composition fixture, not a replacement for the API's
// deliberately unconfigured production PublisherReconciler.
type resourcePublisher struct {
	input resourceInput
	emit  func(context.Context, string, string) error
	sent  bool
}

var _ pubsubruntime.PublisherProvider = (*resourcePublisher)(nil)

func (p *resourcePublisher) EnsureActive(ctx context.Context, publisher pubsubmodel.Publisher, channel pubsubmodel.Channel) error {
	if publisher.Validate() != nil || channel.Validate() != nil {
		return errors.New("invalid Logma resource")
	}
	var config resourceConfig
	if json.Unmarshal(publisher.Config, &config) != nil || publisher.ID != p.input.PublisherID || publisher.Channel != p.input.Channel || channel.Name != p.input.Channel || publisher.Type != "nix-xd-once" || config.Payload != p.input.Payload {
		return errors.New("resource dispatch binding changed")
	}
	if p.sent {
		return nil
	}
	if err := p.emit(ctx, channel.Name, config.Payload); err != nil {
		return err
	}
	p.sent = true
	return nil
}
func resourceDispatch(ctx context.Context, scope string) (result error) {
	data, err := os.ReadFile("/tmp/input.json")
	if err != nil {
		return err
	}
	var input resourceInput
	if json.Unmarshal(data, &input) != nil || input.Channel != scope+":qualification" || !strings.HasPrefix(input.PublisherID, "nix-xd-dispatch-") || len(input.Payload) < 32 {
		return errors.New("invalid scoped resource fixture")
	}
	key, err := secret("/run/credentials/api-key")
	if err != nil {
		return err
	}
	password, err := secret("/run/credentials/redis")
	if err != nil {
		return err
	}
	client := &http.Client{Timeout: 20 * time.Second}
	notFound := errors.New("resource not found")
	request := func(ctx context.Context, method, path string, body any, want int, decoded any) error {
		var reader io.Reader
		if body != nil {
			raw, e := json.Marshal(body)
			if e != nil {
				return e
			}
			reader = bytes.NewReader(raw)
		}
		req, e := http.NewRequestWithContext(ctx, method, "http://logma:8080"+path, reader)
		if e != nil {
			return e
		}
		req.Header.Set("X-API-Key", key)
		req.Header.Set("Content-Type", "application/json")
		response, e := client.Do(req)
		if e != nil {
			return e
		}
		defer response.Body.Close()
		if response.StatusCode == 404 {
			return notFound
		}
		if response.StatusCode != want {
			return fmt.Errorf("Logma resource %s: HTTP %d, expected %d", method, response.StatusCode, want)
		}
		if decoded != nil {
			return json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(decoded)
		}
		return nil
	}
	// Do not mutate or delete a channel that predates this run.
	channelPath := "/pubsub/channels/" + url.PathEscape(input.Channel)
	var channel pubsubmodel.Channel
	channelOwned := false
	publisherOwned := false
	defer func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if publisherOwned {
			if e := request(cleanup, "DELETE", "/pubsub/publishers/"+url.PathEscape(input.PublisherID), nil, 204, nil); e != nil {
				result = fmt.Errorf("publisher cleanup: %w", e)
				return
			}
		}
		if channelOwned {
			if e := request(cleanup, "DELETE", channelPath, nil, 204, nil); e != nil {
				result = fmt.Errorf("channel cleanup: %w", e)
				return
			}
		}
		if result == nil {
			fmt.Println("LOGMA_RESOURCE_CLEANUP=passed")
		}
	}()
	err = request(ctx, "GET", channelPath, nil, 200, &channel)
	if errors.Is(err, notFound) {
		if err = request(ctx, "POST", "/pubsub/channels", pubsubmodel.Channel{Name: input.Channel}, 201, &channel); err != nil {
			return err
		}
		channelOwned = true
	} else if err != nil {
		return err
	}
	config, _ := json.Marshal(resourceConfig{Payload: input.Payload})
	wanted := pubsubmodel.Publisher{ID: input.PublisherID, Channel: input.Channel, Type: "nix-xd-once", Config: config}
	if err = request(ctx, "POST", "/pubsub/publishers", wanted, 201, nil); err != nil {
		return err
	}
	publisherOwned = true
	var publisher pubsubmodel.Publisher
	if err = request(ctx, "GET", "/pubsub/publishers/"+url.PathEscape(input.PublisherID), nil, 200, &publisher); err != nil {
		return err
	}
	if err = request(ctx, "GET", channelPath, nil, 200, &channel); err != nil {
		return err
	}
	fmt.Println("LOGMA_RESOURCE_READBACK=passed")
	redisClient := redis.NewClient(&redis.Options{Network: "unix", Addr: "/run/redis/redis.sock", Username: "logma", Password: password, Protocol: 2})
	defer redisClient.Close()
	producer := &resourcePublisher{input: input, emit: func(ctx context.Context, channel, payload string) error {
		n, e := redisClient.Publish(ctx, channel, payload).Result()
		if e != nil {
			return e
		}
		if n < 1 {
			return errors.New("no subscriber received resource dispatch")
		}
		return nil
	}}
	if err = producer.EnsureActive(ctx, publisher, channel); err != nil {
		return err
	}
	fmt.Println("LOGMA_RESOURCE_DISPATCH=passed")
	return nil
}
