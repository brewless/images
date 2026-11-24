#!/usr/bin/env bash
# Looks for a PHP minor that FrankenPHP publishes and php-versions does not list yet (BL-305). The
# candidates after the newest line of php-versions (say 8.6) are the next minor (8.7) and the next
# major's first (9.0). A candidate counts once Docker Hub's dunglas/frankenphp has a stable tag for it,
# 1-php8.7.<n> with digits only, so no alpha, beta or RC. A found minor is appended to php-versions
# and gets its place in the version check of the Dockerfiles (add_to_guard); then it looks again from
# the new newest, so two minors out at once both come in.
#
# Prints the minors it added as a JSON list, ["8.7"], or [] when there is none. Run from the
# repository root. Used by .github/workflows/runtime-updates.yml, before "Compare PHP releases",
# which then finds no image of ours for the new minor and publishes one.
set -euo pipefail

FILE="${PHP_VERSIONS_FILE:-php-versions}"
DOCKERFILES="${DOCKERFILES:-Dockerfile realtime/Dockerfile}"

# upstream() of php-releases.sh: the newest stable FrankenPHP release of a minor, or nothing.
# shellcheck source=scripts/php-releases.sh
source "$(dirname "${BASH_SOURCE[0]}")/php-releases.sh"

# The version check in a Dockerfile reads, on one line:
#   $min = ["8.3" => "8.3.37", "8.4" => "8.4.28", "8.5" => "8.5.13"][PHP_MAJOR_VERSION...] ?? "8.6.0"
# The minimum of the newest version is the fallback after ??. A new newest moves the old one into the
# map with the minimum it had, and becomes the fallback with its own newest release, so the check
# neither loosens for the old one nor refuses the new one.
add_to_guard() {
  local file="$1" previous="$2" minimum="$3" fallback
  fallback=$(grep -o '\$min = \[[^]]*\]\[[^]]*\] ?? "[0-9.]*"' "$file" | sed -E 's/.*\?\? "([0-9.]+)"$/\1/')
  if [ -z "$fallback" ]; then
    echo "::error::No version check found in $file" >&2
    return 1
  fi
  sed -i.bak -E "s/(\\\$min = \[[^]]*)\](\[[^]]*\]) \?\? \"${fallback//./\\.}\"/\1, \"$previous\" => \"$fallback\"]\2 ?? \"$minimum\"/" "$file"
  rm -f "$file.bak"
}

# The minors that may follow one: 8.6 is followed by 8.7 or by 9.0.
candidates() {
  local major="${1%%.*}" minor="${1#*.}"
  echo "$major.$((minor + 1))"
  echo "$((major + 1)).0"
}

added=()
while :; do
  newest=$(grep -E '^[0-9]+\.[0-9]+$' "$FILE" | tail -n 1)
  found=""
  for candidate in $(candidates "$newest"); do
    # Docker Hub not answering is not a new minor; the next hour asks again.
    release=$(upstream "$candidate" || true)
    if [ -n "$release" ]; then
      found="$candidate"
      break
    fi
  done
  [ -n "$found" ] || break

  echo "$found" >> "$FILE"
  for dockerfile in $DOCKERFILES; do
    if [ -f "$dockerfile" ] && grep -q '\$min = \[' "$dockerfile"; then
      add_to_guard "$dockerfile" "$newest" "$release"
    fi
  done
  added+=("$found")
  echo "::notice::PHP $found is out at FrankenPHP ($release); it is added to php-versions." >&2
done

if [ "${#added[@]}" -eq 0 ]; then
  echo '[]'
else
  printf '%s\n' "${added[@]}" | jq -R . | jq -cs .
fi
