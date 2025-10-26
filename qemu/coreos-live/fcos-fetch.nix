{ pkgs }:

{ version ? "latest", stream ? "stable", arch ? "x86_64", lockFile, useLock ? false }:

let
  fetchMeta = pkgs.runCommand "fcos-meta" { buildInputs = [ pkgs.curl pkgs.jq ]; } ''
    set -euo pipefail
    mkdir -p $out

    JSON_URL="https://builds.coreos.fedoraproject.org/streams/${stream}.json"
    if [ "${version}" = "latest" ]; then
      VERSION=$(curl -s "$JSON_URL" | jq -r ".architectures.${arch}.artifacts.live.release")
    else
      VERSION="${version}"
    fi

    ISO_URL=$(curl -s "$JSON_URL" | jq -r ".architectures.${arch}.artifacts.live.formats.iso.disk.location")
    CHECKSUM_URL="${ISO_URL%/*}/CHECKSUMS"
    SIG_URL="${CHECKSUM_URL}.sig"

    curl -s -o $out/CHECKSUMS "$CHECKSUM_URL"
    curl -s -o $out/CHECKSUMS.sig "$SIG_URL"
    curl -s -o $out/version.txt -L "$JSON_URL"

    echo "$VERSION" > $out/version
    echo "$ISO_URL" > $out/url
  '';

  verifiedSha = pkgs.runCommand "fcos-sha" { buildInputs = [ pkgs.gnupg pkgs.curl pkgs.coreutils pkgs.jq pkgs.nix ]; } ''
    set -euo pipefail
    mkdir -p $out

    VERSION=$(cat ${fetchMeta}/version)
    ISO_URL=$(cat ${fetchMeta}/url)
    CHECKSUMS=${fetchMeta}/CHECKSUMS
    SIG=${fetchMeta}/CHECKSUMS.sig

    if ! gpg --list-keys "Fedora CoreOS Signing" >/dev/null 2>&1; then
      curl -s https://getfedora.org/static/fedora.gpg | gpg --import
    fi
    gpg --verify "$SIG" "$CHECKSUMS"

    SHA256=$(grep "fedora-coreos-${VERSION}-live.${arch}.iso" "$CHECKSUMS" | awk '{print $1}')
    NIX_SHA=$(nix hash convert --to nix-base32 "sha256-${SHA256}")

    cat > $out/lock.json <<EOF
    {
      "version": "${VERSION}",
      "url": "${ISO_URL}",
      "sha256": "sha256-${NIX_SHA}"
    }
    EOF
  '';

  lock = if useLock
         then builtins.fromJSON (builtins.readFile lockFile)
         else builtins.fromJSON (builtins.readFile "${verifiedSha}/lock.json");

in
  pkgs.fetchurl {
    url = lock.url;
    sha256 = lock.sha256;
  }
