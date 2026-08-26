#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
repo_root="$(cd .. && pwd)"

docker run \
  --rm \
  --user "$(id -u):$(id -g)" \
  --env CGO_ENABLED=0 \
  --env GOCACHE=/tmp/go-cache \
  --volume "${repo_root}:/src" \
  --workdir /src \
  golang:1.25-alpine \
  go build -trimpath -ldflags="-s -w" -o terraform/files/agni-security-cell-agent ./cmd/security-cell-agent

docker run \
  --interactive \
  --rm \
  --security-opt label=disable \
  --volume "${PWD}:/pwd" \
  --workdir /pwd \
  quay.io/coreos/butane:release \
  --pretty \
  --strict \
  --files-dir files \
  < config.bu > config.ign
