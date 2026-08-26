#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

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
