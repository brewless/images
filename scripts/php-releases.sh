#!/usr/bin/env bash
# Prints, per PHP version, the newest release FrankenPHP publishes, the release
# in our published brewless-base image and the minimum the Dockerfile asks:
#
#   8.4 upstream=8.4.28 ours=8.4.27 guard=8.4.27
#
# Reads Docker Hub and ghcr.io without a key. Used by .github/workflows/patches.yml.
set -euo pipefail

VERSIONS="${VERSIONS:-8.3 8.4 8.5 8.6}"
OWNER="${OWNER:-brewless}"

upstream() {
  curl -fsS "https://hub.docker.com/v2/repositories/dunglas/frankenphp/tags?page_size=100&ordering=last_updated&name=php$1." \
    | jq -r --arg v "$1" '.results[].name | select(test("^1-php" + ($v | gsub("\\."; "\\.")) + "\\.[0-9]+$")) | sub("^1-php"; "")' \
    | sort -V | tail -n 1
}

ours() {
  local repo="$OWNER/brewless-base" token manifest config
  token=$(curl -fsS "https://ghcr.io/token?scope=repository:$repo:pull" | jq -r .token)
  manifest=$(curl -fsS -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/$repo/manifests/php$1") || { echo ""; return; }
  # A list per platform: ours are built for linux/amd64 only.
  local platform
  platform=$(echo "$manifest" | jq -r '.manifests[]? | select(.platform.architecture == "amd64" and .platform.os == "linux") | .digest' | head -n 1)
  if [ -n "$platform" ]; then
    manifest=$(curl -fsS -H "Authorization: Bearer $token" \
      -H 'Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
      "https://ghcr.io/v2/$repo/manifests/$platform")
  fi
  config=$(echo "$manifest" | jq -r .config.digest)
  curl -fsSL -H "Authorization: Bearer $token" "https://ghcr.io/v2/$repo/blobs/$config" \
    | jq -r '.config.Env[] | select(startswith("PHP_VERSION=")) | sub("^PHP_VERSION="; "")'
}

guard() {
  # The map in the Dockerfile's version check: ["8.3" => "8.3.37", "8.4" => "8.4.28", "8.5" => "8.5.13"] ?? "8.6.0".
  # A version in the map has its own minimum; the newest one is the fallback after ??.
  local line
  line=$(grep -o '\$min = \[[^]]*\][^?]*?? "[0-9.]*"' Dockerfile)
  if echo "$line" | grep -q "\"$1\" =>"; then
    echo "$line" | grep -o "\"$1\" => \"[0-9.]*\"" | sed -E 's/.*=> "([0-9.]+)"/\1/'
  else
    echo "$line" | sed -E 's/.*\?\? "([0-9.]+)".*/\1/'
  fi
}

for v in $VERSIONS; do
  echo "$v upstream=$(upstream "$v") ours=$(ours "$v") guard=$(guard "$v")"
done
