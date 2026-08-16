#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

mkdir -p "$sandbox/bin" "$sandbox/repo"

cat > "$sandbox/bin/copilot" <<'EOF'
#!/usr/bin/env bash
for argument in "$@"; do
	if [ "$argument" = "--no-banner" ]; then
		echo "error: unknown option '--no-banner'" >&2
		exit 2
	fi
done
printf '%s\n' "$@" > "$COPILOT_ARGS_FILE"
printf 'fix(cli): generate commit messages with copilot\n'
EOF
chmod +x "$sandbox/bin/copilot"

git -C "$sandbox/repo" init -q
git -C "$sandbox/repo" config user.name Test
git -C "$sandbox/repo" config user.email test@example.com
printf 'before\n' > "$sandbox/repo/file.txt"
git -C "$sandbox/repo" add file.txt
git -C "$sandbox/repo" commit -qm initial
printf 'after\n' > "$sandbox/repo/file.txt"
git -C "$sandbox/repo" add file.txt

output="$(cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" COPILOT_ARGS_FILE="$sandbox/copilot-args" "$repo_root/bin/git-auto-commit" --print --no-gitmoji)"

test "$output" = 'fix(cli): generate commit messages with copilot'
grep -qx -- '--model=gemini-3.5-flash' "$sandbox/copilot-args"
grep -qx -- '--prompt' "$sandbox/copilot-args"
grep -qx -- '--silent' "$sandbox/copilot-args"
grep -qx -- '--no-custom-instructions' "$sandbox/copilot-args"
grep -qx -- '--disable-builtin-mcps' "$sandbox/copilot-args"
grep -qx -- '--available-tools=' "$sandbox/copilot-args"
! grep -qx -- '--no-banner' "$sandbox/copilot-args"

printf 'git-auto-commit Copilot CLI checks passed.\n'

# --- Test: --no-gitmoji disables emoji prefix ---
cat > "$sandbox/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$COPILOT_ARGS_FILE"
printf 'fix(cli): generate commit messages with copilot\n'
EOF
chmod +x "$sandbox/bin/copilot"

output_no_gitmoji="$(cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" COPILOT_ARGS_FILE="$sandbox/copilot-args" "$repo_root/bin/git-auto-commit" --print --no-gitmoji)"

test "$output_no_gitmoji" = 'fix(cli): generate commit messages with copilot'
# The prompt should NOT contain gitmoji rules when --no-gitmoji is passed.
! grep -q 'GITMOJI' "$sandbox/copilot-args"

printf 'git-auto-commit --no-gitmoji check passed.\n'

# --- Test: default (gitmoji enabled) prepends emoji ---
cat > "$sandbox/bin/copilot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$COPILOT_ARGS_FILE"
printf 'fix(cli): generate commit messages with copilot\n'
EOF
chmod +x "$sandbox/bin/copilot"

output_gitmoji="$(cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" COPILOT_ARGS_FILE="$sandbox/copilot-args" "$repo_root/bin/git-auto-commit" --print)"

# Should start with an emoji (non-ASCII character) followed by the commit message
# Use LC_ALL=C to detect non-ASCII bytes reliably across platforms.
if printf '%s' "$output_gitmoji" | LC_ALL=C grep -q '[^[:print:][:space:]]' && \
   printf '%s' "$output_gitmoji" | grep -q 'fix(cli):'; then
  printf 'git-auto-commit gitmoji default check passed.\n'
else
  printf 'FAIL: expected emoji prefix, got: %s\n' "$output_gitmoji" >&2
  exit 1
fi

# The prompt SHOULD contain gitmoji rules when gitmoji is enabled (default)
grep -q 'GITMOJI' "$sandbox/copilot-args" || {
  printf 'FAIL: expected GITMOJI rules in prompt\n' >&2
  exit 1
}

printf 'git-auto-commit gitmoji prompt rules check passed.\n'