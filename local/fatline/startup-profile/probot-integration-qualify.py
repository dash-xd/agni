#!/usr/bin/env python3
"""Pinned VM1 Probot ACL and Skymill idle-redelivery contract, no external deps."""
import argparse
import base64
import json
import secrets
import socket
import time
import urllib.error
import urllib.request

SCOPE = "fatline-arm-vm1"
STATE = "xd-dash:fatline:runtime:probot-runtime:probot-test"
STREAM = "http://skymill:8081"

def resp(sock, *args):
    data = b"*" + str(len(args)).encode() + b"\r\n"
    for item in args:
        encoded = str(item).encode()
        data += b"$" + str(len(encoded)).encode() + b"\r\n" + encoded + b"\r\n"
    sock.sendall(data)
    with sock.makefile("rb") as stream:
        return read_resp(stream)

def read_resp(stream):
    line = stream.readline()
    if not line or not line.endswith(b"\r\n"):
        raise RuntimeError("Redis response incomplete")
    prefix, value = line[:1], line[1:-2]
    if prefix == b"-":
        return ("error", value.decode("utf-8", "replace"))
    if prefix == b"+":
        return ("ok", value.decode())
    if prefix == b":":
        return ("integer", int(value))
    if prefix == b"$":
        size = int(value)
        if size == -1:
            return ("null", None)
        if size < 0 or size > 4096:
            raise RuntimeError("Redis response size invalid")
        raw = stream.read(size + 2)
        if len(raw) != size + 2 or raw[-2:] != b"\r\n":
            raise RuntimeError("Redis bulk response invalid")
        return ("bulk", raw[:-2])
    if prefix == b"*":
        size = int(value)
        if size == -1:
            return ("null", None)
        if size < 0 or size > 128:
            raise RuntimeError("Redis array size invalid")
        return ("array", [read_resp(stream) for _ in range(size)])
    raise RuntimeError("Unexpected Redis RESP prefix")

def check(reply, expected, label):
    if reply[0] != expected:
        raise RuntimeError(f"{label}: expected {expected}, received {reply[0]}")

def denied(reply, label):
    if reply[0] != "error" or not reply[1].startswith("NOPERM"):
        raise RuntimeError(f"{label}: expected Redis NOPERM")

def redis_principal(role, password):
    with socket.create_connection(("redis-proxy", 6379), timeout=8) as sock:
        sock.settimeout(8)
        check(resp(sock, "AUTH", role, password), "ok", "auth")
        check(resp(sock, "PING"), "ok", "ping")
        denied(resp(sock, "ACL", "LIST"), role + " ACL listing")
        denied(resp(sock, "FUNCTION", "LIST"), role + " functions")
        if role == "probot_state":
            check(resp(sock, "GET", STATE + ":qualification:missing"), "null", "state own key")
            check(resp(sock, "GET", "xd-dash:fatline:auth:binding-artifact:qualification-missing"), "null", "state binding key")
            denied(resp(sock, "GET", SCOPE + ":logma:lifecycle:qualification"), "state foreign Logma key")
            denied(resp(sock, "GET", "skymill:{ffffffffffffffffffffffffffffffff}:qualification"), "state foreign Skymill key")
            denied(resp(sock, "PUBLISH", SCOPE + ":logma:lifecycle:probot-runtime:qualification", "probe"), "state publish")
        elif role == "lifecycle_publish":
            denied(resp(sock, "GET", STATE + ":qualification"), "publisher reads")
            denied(resp(sock, "PUBLISH", "foreign:qualification", "probe"), "publisher cross-channel")
            nonce = secrets.token_hex(12)
            check(resp(sock, "PUBLISH", SCOPE + ":logma:lifecycle:probot-runtime:qualification:" + nonce, "agni-qualification"), "integer", "publisher scoped channel")
        else:
            raise RuntimeError("Unknown Redis principal")
    print(f"AGNI_PROBOT_ACL=passed role={role} foreign_keys=denied foreign_channels=denied", flush=True)

def http(method, path, token, body=None, timeout=15):
    raw = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    request = urllib.request.Request(STREAM + path, data=raw, method=method,
                                     headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                raise RuntimeError(f"Skymill endpoint failed: {path} status={response.status}")
            return json.loads(response.read(1 << 18))
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Skymill endpoint rejected {path}: status={exc.code}") from None

def redelivery(token):
    before = http("GET", "/v1/status", token)
    pending = before.get("Pending", {}).get("Count")
    if pending != 0:
        raise RuntimeError("Skymill has pending deliveries; refusing shared stream fixture")
    nonce = secrets.token_hex(24)
    msg = {"idempotency_key": nonce, "message_id": nonce,
           "payload_base64": base64.b64encode(("agni-retry:" + nonce).encode()).decode()}
    own_id = None
    settled = False
    try:
        result = http("POST", "/v1/messages", token, msg)
        if result.get("duplicate") is not False:
            raise RuntimeError("unexpected duplicate synthetic message")
        own_id = result.get("provider_delivery_id")
        if not own_id:
            raise RuntimeError("no provider delivery ID")
        first = http("POST", "/v1/deliveries/receive", token, {"limit": 1})
        entries = first.get("deliveries", [])
        if len(entries) != 1 or entries[0].get("provider_delivery_id") != own_id or entries[0].get("message", {}).get("id") != nonce:
            raise RuntimeError("unexpected delivery; not NACKing unrelated message")
        original_attempt = entries[0].get("attempt")
        if not isinstance(original_attempt, int):
            raise RuntimeError("missing delivery attempt")
        if http("POST", "/v1/deliveries/nack", token, {"provider_delivery_id": own_id}).get("ok") is not True:
            raise RuntimeError("NACK API unsuccessful")
        pending = http("GET", "/v1/status", token).get("Pending", {}).get("Count")
        if pending != 1:
            raise RuntimeError("NACK did not preserve exactly one pending fixture")
        deadline = time.monotonic() + 100
        while time.monotonic() < deadline:
            try:
                received = http("POST", "/v1/deliveries/receive", token, {"limit": 1}, timeout=14)
            except (urllib.error.URLError, TimeoutError):
                continue
            entries = received.get("deliveries", [])
            if not entries:
                continue
            if len(entries) != 1 or entries[0].get("provider_delivery_id") != own_id or entries[0].get("message", {}).get("id") != nonce:
                raise RuntimeError("unexpected redelivery; not ACKing unrelated message")
            attempt = entries[0].get("attempt")
            if not isinstance(attempt, int) or attempt <= original_attempt:
                raise RuntimeError("redelivery did not increase attempt count")
            if http("POST", "/v1/deliveries/ack", token, {"provider_delivery_id": own_id}).get("ok") is not True:
                raise RuntimeError("failed to ACK synthetic redelivery")
            settled = True
            final = http("GET", "/v1/status", token)
            if final.get("Pending", {}).get("Count") != 0:
                raise RuntimeError("pending deliveries remain after fixture ACK")
            print("AGNI_SKYMILL_REDELIVERY=passed nack_pending=true claimed=true attempt_increased=true ack=true", flush=True)
            return
        raise RuntimeError("Skymill idle claim did not redeliver within bounded window")
    finally:
        if own_id and not settled:
            try:
                http("POST", "/v1/deliveries/ack", token, {"provider_delivery_id": own_id})
            except Exception:
                print("AGNI_SKYMILL_FIXTURE_CLEANUP=blocked manual_reconciliation_required=true", flush=True)

def load(path):
    with open(path, "rb") as f:
        value = f.read().decode().removesuffix("\n")
    if not value or any(c.isspace() for c in value):
        raise RuntimeError("Invalid credential format")
    return value

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-file", required=True)
    parser.add_argument("--publish-file", required=True)
    parser.add_argument("--skymill-token-file", required=True)
    args = parser.parse_args()
    redis_principal("probot_state", load(args.state_file))
    redis_principal("lifecycle_publish", load(args.publish_file))
    print("AGNI_PROBOT_ACL=passed principals=2 bootstrap=unchanged", flush=True)
    redelivery(load(args.skymill_token_file))
