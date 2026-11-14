#!/usr/bin/env python3
"""Bounded live HTTP qualification for the pinned VM1 webhook composition."""
import argparse
import base64
import json
import secrets
import urllib.error
import urllib.request

def request(url, method="GET", body=None, token=None, expected=200):
    payload = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            code = response.status
            raw = response.read(1 << 18)
            content_type = response.headers.get("Content-Type", "")
    except urllib.error.HTTPError as error:
        code = error.code
        raw = error.read(1 << 16)
        content_type = error.headers.get("Content-Type", "")
    if code != expected:
        raise RuntimeError(f"unexpected HTTP status for {method} {url}: {code} (expected {expected})")
    if expected != 200:
        return None
    if url.endswith("/lifecycle/readyz"):
        if content_type.split(";")[0].strip() != "text/plain" or raw.strip() != b"ready":
            raise RuntimeError("Logma strict readiness body mismatch")
        return None
    if url == "http://probot:3000/":
        return None
    return json.loads(raw)

def qualify(token):
    if not (len(token) == 64 and all(c in "0123456789abcdef" for c in token)):
        raise RuntimeError("Skymill bearer credential must be a raw 64-character hex token")
    base = "http://skymill:8081"
    request(base + "/v1/status", expected=401)
    initial = request(base + "/v1/status", token=token)
    pending = initial.get("Pending")
    if not isinstance(pending, dict) or not isinstance(pending.get("Count"), int):
        raise RuntimeError("unexpected Skymill status schema")
    if pending["Count"] != 0:
        raise RuntimeError("consumer group has pending deliveries; refusing to consume unrelated messages")
    request("http://logma:8080/lifecycle/readyz")
    request("http://probot:3000/")
    request("http://probot:3000/probot/deliveries/missing", expected=401)
    print("AGNI_RUNTIME_HTTP=passed logma_ready=true probot_http=true operator_auth=denied skymill_auth=denied", flush=True)
    nonce = secrets.token_hex(24)
    message = {"idempotency_key": nonce, "message_id": nonce,
               "payload_base64": base64.b64encode(("agni-qualification:" + nonce).encode()).decode()}
    first = request(base + "/v1/messages", "POST", message, token)
    second = request(base + "/v1/messages", "POST", message, token)
    if first.get("duplicate") is not False or second.get("duplicate") is not True:
        raise RuntimeError("Skymill publish-once idempotency not preserved")
    if first.get("provider_delivery_id") != second.get("provider_delivery_id"):
        raise RuntimeError("Skymill duplicate source identity changed")
    deliveries = request(base + "/v1/deliveries/receive", "POST", {"limit": 1}, token)
    entries = deliveries.get("deliveries", [])
    if len(entries) != 1 or entries[0].get("message", {}).get("id") != nonce:
        raise RuntimeError("Skymill delivered a different message; refusing to ACK it")
    entry = entries[0]
    if entry.get("provider_delivery_id") != first["provider_delivery_id"]:
        raise RuntimeError("Skymill provider delivery identity changed")
    if entry["message"].get("payload_base64") != message["payload_base64"]:
        raise RuntimeError("Skymill delivery payload mismatch")
    identity = {"provider_delivery_id": entry["provider_delivery_id"]}
    nack = request(base + "/v1/deliveries/nack", "POST", identity, token)
    if nack.get("ok") is not True:
        raise RuntimeError("Skymill NACK API rejected selected delivery")
    ack = request(base + "/v1/deliveries/ack", "POST", identity, token)
    if ack.get("ok") is not True:
        raise RuntimeError("Skymill ACK rejected selected delivery")
    final = request(base + "/v1/status", token=token)
    if not isinstance(final.get("Pending"), dict) or final["Pending"].get("Count") != 0:
        raise RuntimeError("Skymill pending state not cleared after ACK")
    print("AGNI_RUNTIME_SKYMILL=passed publish_once=true delivery_id=opaque ack=true nack_api=true retry=unqualified", flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--token-file", required=True)
    args = parser.parse_args()
    with open(args.token_file, "rb") as credential:
        token = credential.read().decode()
    qualify(token)
