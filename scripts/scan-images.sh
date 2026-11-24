#!/usr/bin/env bash
# Scans the published images with Trivy for CRITICAL and HIGH vulnerabilities and prints one JSON
# document: [{"image": "brewless-base:php8.4", "findings": [{"id", "severity", "package", "installed",
# "fixed", "type"}]}]. `fixed` is null when no fix is out yet; `type` is what Trivy found it in
# (debian, alpine, composer, gobinary, ...). Used by .github/workflows/runtime-updates.yml.
set -euo pipefail

OWNER="${OWNER:-brewless}"
VERSIONS="${VERSIONS:-8.3 8.4 8.5 8.6}"
# Pinned: a scanner that changes under us changes what we rebuild for.
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.58.1}"

images=()
for v in $VERSIONS; do images+=("brewless-base:php$v" "brewless-builder:php$v"); done
images+=("brewless-realtime:$(tr -d '[:space:]' < realtime/VERSION)")

echo '['
first=true
for image in "${images[@]}"; do
  report=$(docker run --rm -v trivy-cache:/root/.cache "$TRIVY_IMAGE" image --quiet --scanners vuln \
    --severity CRITICAL,HIGH --format json "ghcr.io/$OWNER/$image" 2>/dev/null || echo '{}')
  findings=$(echo "$report" | jq -c '[.Results[]? as $r | $r.Vulnerabilities[]? | {
      id: .VulnerabilityID, severity: .Severity, package: .PkgName,
      installed: .InstalledVersion, fixed: (if (.FixedVersion // "") == "" then null else .FixedVersion end),
      type: $r.Type }] | unique_by(.id + "|" + .package)')
  $first || echo ','
  first=false
  jq -cn --arg image "$image" --argjson findings "$findings" '{image: $image, findings: $findings}'
done
echo ']'
