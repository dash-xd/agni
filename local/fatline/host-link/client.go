package main

import (
 "context"
 "encoding/json"
 "errors"
 "flag"
 "fmt"
 "net"
 "os"
 "strings"
 "syscall"
 "time"

 "github.com/redis/go-redis/v9"
 logmapubsub "github.com/xd-dash/logma/serverless/pubsub"
)

type config struct {
 Network string `json:"network"`
 Address string `json:"address"`
 Username string `json:"username"`
 PasswordFile string `json:"passwordFile"`
 Scope string `json:"scope"`
 Channel string `json:"channel"`
 Payload string `json:"payload"`
}

func denied(err error) bool { return err != nil && strings.HasPrefix(err.Error(), "NOPERM") }

func execute(mode, file, socket string) error {
 ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
 defer cancel()
 if mode == "deny-socket" {
  conn, err := (&net.Dialer{Timeout: 5*time.Second}).DialContext(ctx, "unix", socket)
  if conn != nil { conn.Close() }
  if !errors.Is(err, syscall.EACCES) { return fmt.Errorf("expected POSIX EACCES, got %v", err) }
  fmt.Println("HOST_LINK_POSIX_DENIAL=passed")
  return nil
 }
 data, err := os.ReadFile(file)
 if err != nil { return fmt.Errorf("read configuration: %w", err) }
 var c config
 if err := json.Unmarshal(data, &c); err != nil { return err }
 if (c.Network != "unix" && c.Network != "tcp") || c.Address == "" || c.Scope == "" ||
  c.Channel != c.Scope+":qualification" || c.Payload == "" { return errors.New("invalid scoped configuration") }
 secret, err := os.ReadFile(c.PasswordFile)
 if err != nil { return fmt.Errorf("read credential: %w", err) }
 password := strings.TrimSpace(string(secret))
 if len(password) < 32 { return errors.New("invalid credential") }
 client := redis.NewClient(&redis.Options{Network:c.Network, Addr:c.Address, Username:c.Username,
  Password:password, DB:0, Protocol:2, DialTimeout:15*time.Second, ReadTimeout:15*time.Second, WriteTimeout:15*time.Second})
 defer client.Close()
 if mode == "unauthenticated" {
  client.Close()
  anonymous := redis.NewClient(&redis.Options{Network:c.Network, Addr:c.Address, Protocol:2, DialTimeout:10*time.Second, ReadTimeout:10*time.Second})
  defer anonymous.Close()
  err := anonymous.Ping(ctx).Err()
  if err == nil || !strings.Contains(err.Error(), "NOAUTH") { return errors.New("anonymous access did not fail with NOAUTH") }
  fmt.Println("HOST_LINK_UNAUTHENTICATED=denied")
  return nil
 }
 if err := client.Ping(ctx).Err(); err != nil { return fmt.Errorf("authenticated ping: %w", err) }
 switch mode {
 case "subscribe":
  received := make(chan struct{}, 1)
  sub := logmapubsub.Subscribe(ctx, client, c.Channel, func(message string) {
   if message == c.Payload { select { case received <- struct{}{}: default: } }
  })
  select { case <-sub.Ready(): fmt.Println("HOST_LINK_SUBSCRIBER_READY=true")
   case <-ctx.Done(): return errors.New("subscriber readiness timed out") }
  select { case <-received:
   cancel()
   select { case <-sub.Stopped(): case <-time.After(10*time.Second): return errors.New("subscriber did not stop") }
   fmt.Println("HOST_LINK_MESSAGE=passed")
   return nil
   case <-ctx.Done(): return errors.New("subscriber delivery timed out") }
 case "publish":
  n, err := client.Publish(ctx, c.Channel, c.Payload).Result()
  if err != nil { return err }
  if n < 1 { return errors.New("no acknowledged subscriber") }
  fmt.Println("HOST_LINK_PUBLISH=passed")
  return nil
 case "check":
  for _, command := range [][]interface{}{{"SELECT",1}, {"ACL","LIST"}, {"CONFIG","GET","*"},
   {"FUNCTION","LIST"}, {"PUBLISH", "foreign:qualification", "denied"}, {"GET", "foreign:key"}} {
   if err := client.Do(ctx, command...).Err(); !denied(err) { return fmt.Errorf("expected NOPERM for %v", command[0]) }
  }
  subscription := client.Subscribe(ctx, "foreign:qualification")
  _, err := subscription.Receive(ctx)
  subscription.Close()
  if !denied(err) { return errors.New("foreign channel subscription was not denied") }
  if c.Username == "publisher" {
   if err := client.Set(ctx, c.Scope+":qualification:key", "scoped", 0).Err(); err != nil { return err }
   value, err := client.Get(ctx, c.Scope+":qualification:key").Result()
   if err != nil || value != "scoped" { return errors.New("scoped key operation failed") }
   if !denied(client.Set(ctx, "foreign:key", "denied", 0).Err()) { return errors.New("foreign write was not denied") }
  } else {
   if !denied(client.Publish(ctx, c.Channel, "denied").Err()) { return errors.New("subscriber could publish") }
   if !denied(client.Get(ctx, c.Scope+":qualification:key").Err()) { return errors.New("subscriber could read keys") }
  }
  fmt.Println("HOST_LINK_ACL=passed")
  return nil
 default: return errors.New("unknown mode")
 }
}

func main() {
 mode := flag.String("mode", "subscribe", "qualification mode")
 file := flag.String("config", "", "runtime configuration file")
 socket := flag.String("socket", "", "negative POSIX probe socket")
 flag.Parse()
 if err := execute(*mode, *file, *socket); err != nil {
  fmt.Fprintln(os.Stderr, "host-link:", err)
  os.Exit(1)
 }
}
