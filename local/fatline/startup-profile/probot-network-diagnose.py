#!/usr/bin/env python3
"""Network-only VM1 diagnostics; no credentials, Redis writes, or HTTP payloads."""
import socket

ENDPOINTS = (("logma", 8080), ("skymill", 8081), ("probot", 3000), ("redis-proxy", 6379))

def main():
    failed = False
    for name, port in ENDPOINTS:
        try:
            records = socket.getaddrinfo(name, port, type=socket.SOCK_STREAM)
        except OSError as error:
            print(f"AGNI_NETWORK_ENDPOINT name={name} port={port} dns=failed detail={type(error).__name__}", flush=True)
            failed = True
            continue
        addresses = sorted({item[4][0] for item in records})
        try:
            with socket.create_connection((name, port), timeout=5):
                print(f"AGNI_NETWORK_ENDPOINT name={name} port={port} dns=passed tcp=passed addresses={','.join(addresses)}", flush=True)
        except OSError as error:
            print(f"AGNI_NETWORK_ENDPOINT name={name} port={port} dns=passed tcp=failed error={type(error).__name__} addresses={','.join(addresses)}", flush=True)
            failed = True
    print("AGNI_NETWORK_DIAGNOSIS=passed all_endpoints_reachable=true" if not failed else
          "AGNI_NETWORK_DIAGNOSIS=blocked all_endpoints_reachable=false", flush=True)

if __name__ == "__main__":
    main()
