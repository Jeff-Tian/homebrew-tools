#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/scripts" "$sandbox/Formula" "$sandbox/bucket"
cp "$repo_root/scripts/bump-version.sh" "$sandbox/scripts/"
printf 'class Demo < Formula\n  version "0.9.7"\nend\n' > "$sandbox/Formula/demo.rb"
printf '{"version": "0.9.7"}\n' > "$sandbox/bucket/demo.json"

"$sandbox/scripts/bump-version.sh" demo >/dev/null
grep -qx '  version "0.10.0"' "$sandbox/Formula/demo.rb"
test "$(jq -r .version "$sandbox/bucket/demo.json")" = '0.10.0'

"$sandbox/scripts/bump-version.sh" demo 1.2.3 >/dev/null
grep -qx '  version "1.2.3"' "$sandbox/Formula/demo.rb"

printf 'bump-version checks passed.\n'
