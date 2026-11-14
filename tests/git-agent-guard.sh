#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/bin/git-agent-guard"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
expect_blocked() {
  if "$@" > "$sandbox/output" 2>&1; then fail "agent hook allowed operation"; fi
  grep -q 'AI agent session' "$sandbox/output"
}

mkdir -p "$sandbox/repo"
cd "$sandbox/repo"
git init -q

if bash "$tool" init --bogus > "$sandbox/output" 2>&1; then
  fail "unsupported option accepted"
fi
bash "$tool" init
hooks="$(git rev-parse --git-path hooks)"
test -x "$hooks/pre-commit" || fail "pre-commit not installed"
test -x "$hooks/pre-push" || fail "pre-push not installed"
if git config --local --get core.hooksPath; then fail "installer changed hooksPath"; fi
expect_blocked env AI_AGENT=test bash "$hooks/pre-commit"
expect_blocked env COPILOT_AGENT_SESSION_ID=test bash "$hooks/pre-push"

# This only simulates a human while calling hook scripts in the test fixture.
# No commit or push is executed.
env -u AI_AGENT -u COPILOT_AGENT_SESSION_ID bash "$hooks/pre-commit"
env -u AI_AGENT -u COPILOT_AGENT_SESSION_ID bash "$hooks/pre-push"
bash "$tool" init
bash "$tool" check
bash "$tool" uninstall
test ! -e "$hooks/pre-commit"
test ! -e "$hooks/pre-push"

# An inherited hooksPath must not turn a per-repo install into a global change.
printf '[core]\n\thooksPath = %s\n' "$sandbox/shared hooks" > "$sandbox/global-config"
if GIT_CONFIG_GLOBAL="$sandbox/global-config" bash "$tool" init > "$sandbox/output" 2>&1; then
  fail "modified inherited hooks directory"
fi
test ! -e "$sandbox/shared hooks"

git config --local core.hooksPath 'custom hooks'
mkdir -p 'custom hooks'
cat > 'custom hooks/pre-push' <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > hook-args
cat > hook-stdin
exit 7
EOF
chmod +x 'custom hooks/pre-push'
cp 'custom hooks/pre-push' "$sandbox/original"
printf 'DCO untouched\n' > 'custom hooks/prepare-commit-msg'
bash "$tool" init
test "$(git config --local core.hooksPath)" = 'custom hooks'
expect_blocked env AI_AGENT=test bash 'custom hooks/pre-push'
test ! -e hook-args
set +e
printf 'refs/heads/main abc\n' | env -u AI_AGENT -u COPILOT_AGENT_SESSION_ID \
  bash 'custom hooks/pre-push' origin 'remote with spaces'
status=$?
set -e
test "$status" = 7 || fail "original hook exit status lost"
test "$(cat hook-args)" = "$(printf 'origin\nremote with spaces')"
test "$(cat hook-stdin)" = 'refs/heads/main abc'
bash "$tool" init
bash "$tool" uninstall
cmp 'custom hooks/pre-push' "$sandbox/original"
test "$(cat 'custom hooks/prepare-commit-msg')" = 'DCO untouched'

# Do not overwrite or remove hooks edited after installation.
bash "$tool" init
printf '# user edit\n' >> 'custom hooks/pre-push'
cp 'custom hooks/pre-push' "$sandbox/edited"
if bash "$tool" uninstall > "$sandbox/output" 2>&1; then fail "removed edited hook"; fi
cmp 'custom hooks/pre-push' "$sandbox/edited"
if bash "$tool" init > "$sandbox/output" 2>&1; then fail "overwrote edited hook"; fi
cmp 'custom hooks/pre-push' "$sandbox/edited"

mkdir -p "$sandbox/edited-repo"
cd "$sandbox/edited-repo"
git init -q
bash "$tool" init
printf '# user edit\n' >> .git/hooks/pre-push
if bash "$tool" init > "$sandbox/output" 2>&1; then fail "overwrote edited new hook"; fi
grep -q '# user edit' .git/hooks/pre-push

cd "$sandbox"
if bash "$tool" init > "$sandbox/output" 2>&1; then fail "accepted non-repository"; fi
grep -q 'Not inside a git repository' "$sandbox/output"

# ── Global mode: sandboxed HOME and global config, never the real ones ──
export HOME="$sandbox/home" GIT_CONFIG_GLOBAL="$sandbox/home/.gitconfig"
unset XDG_CONFIG_HOME
mkdir -p "$HOME"
ghooks="$HOME/.githooks"

if bash "$tool" check --global > "$sandbox/output" 2>&1; then fail "check passed before install"; fi
bash "$tool" init --global
test "$(git config --global core.hooksPath)" = "$ghooks" || fail "global hooksPath not set"
test -x "$ghooks/pre-commit" || fail "global pre-commit not installed"
test -x "$ghooks/pre-push" || fail "global pre-push not installed"
bash "$tool" init --global
bash "$tool" check --global

mkdir -p "$sandbox/global-repo"
cd "$sandbox/global-repo"
git init -q
expect_blocked env AI_AGENT=test bash "$ghooks/pre-push" origin url
expect_blocked env COPILOT_AGENT_SESSION_ID=test bash "$ghooks/pre-commit"

# A repository's own hook (hidden by the global hooksPath) still runs for humans.
cat > .git/hooks/pre-push <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > repo-hook-args
cat > repo-hook-stdin
exit 5
EOF
chmod +x .git/hooks/pre-push
set +e
printf 'refs/heads/main abc\n' | env -u AI_AGENT -u COPILOT_AGENT_SESSION_ID \
  bash "$ghooks/pre-push" origin 'remote with spaces'
status=$?
set -e
test "$status" = 5 || fail "repo hook exit status lost"
test "$(cat repo-hook-args)" = "$(printf 'origin\nremote with spaces')"
test "$(cat repo-hook-stdin)" = 'refs/heads/main abc'
env -u AI_AGENT -u COPILOT_AGENT_SESSION_ID bash "$ghooks/pre-commit"

# Repository-local hooksPath overrides the global guard: warn, do not modify.
git config --local core.hooksPath .husky
bash "$tool" check --global 2> "$sandbox/output"
grep -q 'does not apply here' "$sandbox/output" || fail "no local override warning"
git config --local --unset core.hooksPath

# Per-repo init refuses while the global path is inherited.
if bash "$tool" init > "$sandbox/output" 2>&1; then fail "per-repo init modified global hooks"; fi
grep -q 'init --global' "$sandbox/output"

bash "$tool" uninstall --global
test ! -e "$ghooks/pre-commit"
test ! -e "$ghooks/pre-push"
test "$(git config --global core.hooksPath)" = "$ghooks" || fail "uninstall changed shared hooksPath"

# Existing global hooks (e.g. git-dco or a custom pre-push) are preserved and chained.
printf 'DCO untouched\n' > "$ghooks/prepare-commit-msg"
printf '#!/bin/sh\nexit 9\n' > "$ghooks/pre-push"
chmod +x "$ghooks/pre-push"
cp "$ghooks/pre-push" "$sandbox/global-original"
bash "$tool" init --global
expect_blocked env AI_AGENT=test bash "$ghooks/pre-push"
set +e
env -u AI_AGENT -u COPILOT_AGENT_SESSION_ID bash "$ghooks/pre-push" < /dev/null
status=$?
set -e
test "$status" = 9 || fail "global original hook not chained"
bash "$tool" uninstall --global
cmp "$ghooks/pre-push" "$sandbox/global-original"
test "$(cat "$ghooks/prepare-commit-msg")" = 'DCO untouched'

# Relative global hooksPath is refused.
git config --global core.hooksPath relative-hooks
if bash "$tool" init --global > "$sandbox/output" 2>&1; then fail "accepted relative hooksPath"; fi

echo 'git-agent-guard checks passed.'
