#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dco="$root/bin/git-dco"
guard="$root/bin/git-agent-guard"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export GIT_CONFIG_GLOBAL="$sandbox/global-config"
export GIT_CONFIG_NOSYSTEM=1

fail() { echo "FAIL: $*" >&2; exit 1; }
init_repo() {
  mkdir -p "$1"
  cd "$1"
  git init -q
  git config user.name Tester
  git config user.email test@example.com
}

for order in dco-first guard-first; do
  for uninstall_order in dco-first guard-first; do
    init_repo "$sandbox/$order-$uninstall_order"
    if [ "$order" = dco-first ]; then
      bash "$dco" init
      bash "$guard" init
    else
      bash "$guard" init
      bash "$dco" init
    fi
    bash "$guard" check || fail "DCO deactivated agent guard"
    hooks="$(git rev-parse --git-path hooks)"
    if git config --local --get core.hooksPath; then fail "hooksPath changed"; fi
    bash "$dco" init
    bash "$guard" init
    printf 'test message\n' > message
    "$hooks/prepare-commit-msg" "$PWD/message" message
    "$hooks/prepare-commit-msg" "$PWD/message" message
    test "$(grep -c '^Signed-off-by: Tester <test@example.com>$' message)" = 1
    if AI_AGENT=test "$hooks/pre-commit" > "$sandbox/output" 2>&1; then
      fail "agent allowed after DCO install"
    fi
    if [ "$uninstall_order" = dco-first ]; then
      bash "$dco" uninstall
      bash "$guard" check
      bash "$guard" uninstall
    else
      bash "$guard" uninstall
      printf 'still needs signoff\n' > message
      "$hooks/prepare-commit-msg" "$PWD/message" message
      grep -q '^Signed-off-by:' message
      bash "$dco" uninstall
    fi
    test ! -e "$hooks/pre-commit"
    test ! -e "$hooks/prepare-commit-msg"
  done
done

init_repo "$sandbox/existing"
git config --local core.hooksPath 'custom hooks'
mkdir -p 'custom hooks'
cat > 'custom hooks/prepare-commit-msg' <<'EOF'
#!/bin/sh
printf 'custom body\n' >> "$1"
printf '%s\n' "$@" > original-args
cat > original-stdin
EOF
chmod +x 'custom hooks/prepare-commit-msg'
cp 'custom hooks/prepare-commit-msg' "$sandbox/original"
bash "$dco" init
bash "$dco" init
printf 'original message\n' > message
printf 'input\n' | 'custom hooks/prepare-commit-msg' "$PWD/message" message
test "$(cat original-args)" = "$(printf '%s\nmessage' "$PWD/message")"
test "$(cat original-stdin)" = input
grep -q '^custom body$' message
grep -q '^Signed-off-by:' message
bash "$dco" uninstall
cmp 'custom hooks/prepare-commit-msg' "$sandbox/original"
test "$(git config --local core.hooksPath)" = 'custom hooks'

printf '#!/bin/sh\nexit 7\n' > 'custom hooks/prepare-commit-msg'
bash "$dco" init
printf 'must remain unchanged\n' > message
set +e
'custom hooks/prepare-commit-msg' "$PWD/message" message
status=$?
set -e
test "$status" = 7 || fail "original hook failure lost"
test "$(cat message)" = 'must remain unchanged'
bash "$dco" uninstall

rm 'custom hooks/prepare-commit-msg'
bash "$dco" init
printf '# user edit\n' >> 'custom hooks/prepare-commit-msg'
cp 'custom hooks/prepare-commit-msg' "$sandbox/edited"
if bash "$dco" init > "$sandbox/output" 2>&1; then fail "overwrote edited DCO hook"; fi
if bash "$dco" uninstall > "$sandbox/output" 2>&1; then fail "removed edited DCO hook"; fi
cmp 'custom hooks/prepare-commit-msg' "$sandbox/edited"

# Upgrade the exact hook shipped by git-dco 0.1.0 without wrapping it twice.
init_repo "$sandbox/legacy"
git config --local core.hooksPath .githooks
mkdir .githooks
cat > .githooks/prepare-commit-msg <<'EOF'
#!/bin/sh
# Auto sign-off for DCO (installed by `git dco`)
COMMIT_MSG_FILE=$1
COMMIT_SOURCE=${2:-}
[ "$COMMIT_SOURCE" = "merge" ] && exit 0
grep -q "^Signed-off-by:" "$COMMIT_MSG_FILE" && exit 0
SOB=$(git var GIT_COMMITTER_IDENT | sed -n "s/^\(.*>\).*$/Signed-off-by: \1/p")
printf "\n%s\n" "$SOB" >> "$COMMIT_MSG_FILE"
EOF
chmod +x .githooks/prepare-commit-msg
bash "$guard" init
bash "$dco" init
bash "$dco" check
test ! -e .githooks/prepare-commit-msg.git-dco-original
test "$(git config --local core.hooksPath)" = .githooks
printf 'legacy message\n' > message
.githooks/prepare-commit-msg "$PWD/message" message
test "$(grep -c '^Signed-off-by:' message)" = 1
bash "$dco" uninstall
bash "$guard" check

# Global installation respects a pre-existing directory, without resetting it.
git config --global core.hooksPath "$sandbox/global hooks"
bash "$dco" init --global
test "$(git config --global core.hooksPath)" = "$sandbox/global hooks"
test -x "$sandbox/global hooks/prepare-commit-msg"
init_repo "$sandbox/inherited"
if bash "$dco" init > "$sandbox/output" 2>&1; then fail "modified inherited global hooks"; fi
if bash "$dco" uninstall > "$sandbox/output" 2>&1; then fail "removed inherited global hook"; fi
test -x "$sandbox/global hooks/prepare-commit-msg"

if bash "$dco" init --unexpected > "$sandbox/output" 2>&1; then fail "unknown option accepted"; fi
echo 'git-dco coexistence checks passed.'
