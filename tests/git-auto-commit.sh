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

output="$(cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" COPILOT_ARGS_FILE="$sandbox/copilot-args" "$repo_root/bin/git-auto-commit" --print)"

test "$output" = 'fix(cli): generate commit messages with copilot'
grep -qx -- '--model=auto' "$sandbox/copilot-args"
grep -qx -- '--prompt' "$sandbox/copilot-args"
grep -qx -- '--silent' "$sandbox/copilot-args"
grep -qx -- '--no-custom-instructions' "$sandbox/copilot-args"
grep -qx -- '--disable-builtin-mcps' "$sandbox/copilot-args"
grep -qx -- '--available-tools=' "$sandbox/copilot-args"
! grep -qx -- '--no-banner' "$sandbox/copilot-args"

printf 'git-auto-commit Copilot CLI checks passed.\n'