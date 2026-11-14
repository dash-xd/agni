#!/usr/bin/env python3
"""Bounded live HTTP qualification for the pinned VM1 webhook composition."""
import argparse
import base64
import json
import secrets
import urllib.error
import urllib.request

def request(url, method="GET", body=None, token=None, api_key=None, expected=200):
    payload = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    headers = {"Content-Type": "application/json"}
    if token is not None:
        headers["Authorization"] = "Bearer " + token
    if api_key is not None:
        headers["X-API-Key"] = api_key
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
    if url == "http://probot:3000/":
        return None
    return json.loads(raw)

def qualify(token, logma_key):
    if not (len(token) == 64 and all(c in "0123456789abcdef" for c in token)):
        raise RuntimeError("Skymill bearer credential must be a raw 64-character hex token")
    base = "http://skymill:8081"
    request(base + "/v1/status", expected=401)
    # The consumer group may not exist until the first receive request.
    # A delivery for another source ID is rejected rather than ACKed.
    # Pinned cmd/api-lifecycle listens on 18081 with a versioned lifecycle API.
    # It has no strict dependency readyz; do not report such readiness as qualified.
    logma_url = "http://logma:18081/lifecycle/api/v0.0.1/policies"
    request(logma_url, expected=401)
    policies = request(logma_url, api_key=logma_key)
    if not isinstance(policies, list) or not policies or not all(
        isinstance(p, dict) and {"name", "policy_code", "duration"} <= p.keys()
        for p in policies
    ):
        raise RuntimeError("Logma lifecycle policies contract mismatch")
    request("http://probot:3000/")
    request("http://probot:3000/probot/deliveries/missing", expected=401)
    print("AGNI_RUNTIME_HTTP=passed logma_api=true logma_strict_ready=unqualified probot_http=true operator_auth=denied skymill_auth=denied", flush=True)
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
    parser.add_argument("--logma-api-key-file", required=True)
    args = parser.parse_args()
    with open(args.token_file, "rb") as credential:
        token = credential.read().decode()
    with open(args.logma_api_key_file, "rb") as credential:
        logma_key = credential.read().decode().removesuffix("\\n")
    if not logma_key or any(c.isspace() for c in logma_key):
        raise RuntimeError("Logma API key credential invalid")
    qualify(token, logma_key)
