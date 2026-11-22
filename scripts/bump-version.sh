#!/usr/bin/env bash
# bump-version — update Formula and Scoop manifest versions.
#
# Usage:
#   ./scripts/bump-version.sh <tool-name> 0.2.4
#   ./scripts/bump-version.sh <tool-name>        # minor bump: 0.5.3 -> 0.6.0
#
# Updates:
#   1. Formula/<tool>.rb  version "x.y.z"
#   2. bucket/<tool>.json  .version, when the Scoop manifest exists
#
# The bin/<tool> script gets its version injected at brew install time
# via inreplace, so it does NOT need manual updates.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <tool-name> [new-version]" >&2
  echo "  e.g. $0 git-auto-commit 0.2.4" >&2
  exit 1
fi

TOOL="$1"
NEW_VERSION="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON="$ROOT/bucket/${TOOL}.json"
FORMULA="$ROOT/Formula/${TOOL}.rb"

if [ ! -f "$FORMULA" ]; then
  echo "✗ Not found: $FORMULA" >&2
  exit 1
fi

if [ -z "$NEW_VERSION" ]; then
  CURRENT="$(sed -nE 's/^  version "([0-9]+)\.([0-9]+)\.[0-9]+"$/\1.\2/p' "$FORMULA")"
  if [ -z "$CURRENT" ]; then
    echo "✗ No x.y.z version in $FORMULA; pass <new-version> explicitly." >&2
    exit 1
  fi
  NEW_VERSION="${CURRENT%%.*}.$(( ${CURRENT#*.} + 1 )).0"
fi

# Update the Scoop manifest for tools that provide one.
if [ -f "$JSON" ]; then
  jq --arg v "$NEW_VERSION" '.version = $v' "$JSON" > "${JSON}.tmp" && mv "${JSON}.tmp" "$JSON"
  echo "✓ Updated $JSON"
fi

# Update formula
sed -i.bak "s/^  version \"[^\"]*\"/  version \"${NEW_VERSION}\"/" "$FORMULA"
rm -f "${FORMULA}.bak"
echo "✓ Updated $FORMULA"

echo "✓ Version bumped to $NEW_VERSION"
