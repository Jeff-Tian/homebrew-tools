#!/usr/bin/env bash
# bump-version — update version across all files from the canonical JSON source.
#
# Usage:
#   ./scripts/bump-version.sh 0.2.4
#
# Updates:
#   1. bucket/<tool>.json  .version
#   2. Formula/<tool>.rb  version "x.y.z"
#
# The bin/<tool> script gets its version injected at brew install time
# via inreplace, so it does NOT need manual updates.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <tool-name> <new-version>" >&2
  echo "  e.g. $0 git-auto-commit 0.2.4" >&2
  exit 1
fi

TOOL="$1"
NEW_VERSION="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON="$ROOT/bucket/${TOOL}.json"
FORMULA="$ROOT/Formula/${TOOL}.rb"

if [ ! -f "$JSON" ]; then
  echo "✗ Not found: $JSON" >&2
  exit 1
fi

if [ ! -f "$FORMULA" ]; then
  echo "✗ Not found: $FORMULA" >&2
  exit 1
fi

# Update JSON
jq --arg v "$NEW_VERSION" '.version = $v' "$JSON" > "${JSON}.tmp" && mv "${JSON}.tmp" "$JSON"
echo "✓ Updated $JSON"

# Update formula
sed -i.bak "s/^  version \"[^\"]*\"/  version \"${NEW_VERSION}\"/" "$FORMULA"
rm -f "${FORMULA}.bak"
echo "✓ Updated $FORMULA"

echo "✓ Version bumped to $NEW_VERSION"
