# homebrew-tools

Personal Homebrew tap for small developer-workflow tools.

## Install the tap

```sh
brew tap jeff-tian/tools https://github.com/Jeff-Tian/homebrew-tools
```

Since the repo is published as `Jeff-Tian/homebrew-tools` on GitHub, the short
form also works:

```sh
brew tap jeff-tian/tools
```

## Install on Windows

Even made it a private repository, use an authenticated clone and run the installer works.
It copies the tool scripts and Windows command wrappers into a user-level bin
directory and updates your user `PATH`; no manual copying is required.

```powershell
# Authenticate once if needed:
gh auth login

# Clone or update the private repository:
$repo = Join-Path $env:LOCALAPPDATA 'JeffTian\homebrew-tools'
if (Test-Path $repo) {
   git -C $repo pull --ff-only
} else {
   gh repo clone Jeff-Tian/homebrew-tools $repo
}

# Install dependencies through Scoop if missing, then install the tools:
& "$repo\install.ps1" -InstallDependencies
```

If the repository is made public, it can also be installed as a Scoop
bucket:

```powershell
scoop bucket add jeff-tian-tools https://github.com/Jeff-Tian/homebrew-tools
scoop install git-auto-commit git-dco
```

If `scoop bucket add` rewrites the URL through an old mirror or proxy such as
`scoop.201704.xyz`, clear the Scoop proxy first with `scoop config rm proxy`.
For a private repository, prefer the authenticated clone installer above;
Scoop's bucket and raw-file downloads are not a good fit for private GitHub
repositories without extra credential plumbing.

After installation, use the tools from PowerShell, Command Prompt, or Git Bash:

```powershell
git auto-commit --version
git dco --version
git dco init
```

`git-auto-commit` supports two AI backends:

- **copilot** (default) — GitHub Copilot CLI. Install it and run `copilot login` once.
- **brickverse** — [Brickverse](https://pub.brickverse.net) model-proxy (Cloudflare Workers AI).
  First run opens a browser for Cloudflare Access login and caches the cookie at
  `~/.cache/brickverse/cf_authorization`. Significantly faster than Copilot CLI
  (~2-5s vs ~25-45s per call).

## Tools

### `git-auto-commit`

Generate a Conventional / Angular-style commit message from the staged diff
using GitHub Copilot CLI, then commit. Inspired by the `auto-releasenotes`
target in [`SimpleMultiApp`](https://github.com/Jeff-Tian/SimpleMultiApp).

```sh
brew install jeff-tian/tools/git-auto-commit

cd ~/some/repo
git add -p                       # stage what you want
git auto-commit                  # AI drafts the message, then asks y/n/edit

# Or in one shot:
git auto-commit -a -y            # stage tracked changes + commit without prompt

# Hint the model:
git auto-commit --type=fix --scope=auth
git auto-commit --scope="auth, ui"          # multiple extra scopes
git auto-commit --ticket=ABC-123            # force a specific ticket id
git auto-commit --no-ticket                 # opt out of ticket auto-prepend
git auto-commit --no-sign-off               # opt out of DCO Signed-off-by trailer

# Switch AI backend:
git auto-commit --backend=brickverse        # use Cloudflare Workers AI (fast)
git auto-commit --backend=copilot           # use GitHub Copilot CLI (default)

# Preview only:
git auto-commit --dry-run
git auto-commit --print          # message to stdout (CI-friendly)
```

Requirements depend on the backend:

- `copilot` backend: `git` + [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli). Authenticate once with `copilot login`.
- `brickverse` backend: `git` + `ruby` (preinstalled on macOS). First run opens a browser to complete Cloudflare Access login.

The model output language follows your recent commit history (中文 commits → 中文 message).

#### Scope & ticket auto-detection

The subject is `<type>(<scope>): <subject>` where `<scope>` is a comma-space
separated list. A ticket id matching `[A-Z][A-Z0-9]+-\d+` (e.g. `ABC-123`)
is detected from, in priority order:

1. `--ticket=…` flag
2. The current branch name — `feature/ABC-123-some-desc` → `ABC-123`
3. Recent commit messages

The ticket becomes the first item in the scope, followed by any `--scope=`
extras and 1-2 scopes the model infers from the diff. Example:

```
feat(ABC-123, auth, ui): add OAuth login screen
```

Pass `--no-ticket` to disable, or set `GIT_AUTO_COMMIT_TICKET_PATTERN` to a
custom regex (e.g. for `#1234` or `JIRA_1234`-style ids).

#### DCO sign-off

By default `git auto-commit` runs `git commit -s`, appending a
`Signed-off-by: Your Name <you@example.com>` trailer so the GitHub DCO check
passes. This is idempotent and safe to combine with the [`git dco`](#git-dco)
hook — git won't add a duplicate trailer. Pass `--no-sign-off` to opt out.

Environment overrides:

| Variable | Default | Purpose |
|---|---|---|
| `GIT_AUTO_COMMIT_BACKEND` | `copilot` | AI backend: `copilot` (Copilot CLI) or `brickverse` (Cloudflare Workers AI) |
| `GIT_AUTO_COMMIT_MODEL` | `gemini-3.5-flash` (copilot)<br>`gpt-oss-120b` (brickverse) | Model name passed to the selected backend |
| `GIT_AUTO_COMMIT_MAX_DIFF` | `12000` (copilot) / `6000` (brickverse) | Truncate the staged diff at N chars before sending. The brickverse default is lower because gpt-oss-120b silently returns an empty completion when the total prompt exceeds ~12–13 KB. |
| `GIT_AUTO_COMMIT_TICKET_PATTERN` | `[A-Z][A-Z0-9]+-[0-9]+` | Regex for ticket id detection |
| `BRICKVERSE_HOST` | `https://pub.brickverse.net` | (brickverse backend only) Override the model-proxy origin |
| `AI_MODEL` | `gpt-oss-120b` | (brickverse backend only) Default model if `--model` / `GIT_AUTO_COMMIT_MODEL` not set |

### `git-dco`

One-shot DCO sign-off hook installer. Adds a `prepare-commit-msg` hook that
appends `Signed-off-by:` to every commit so GitHub's DCO check passes without
having to remember `git commit -s`.

```sh
brew install jeff-tian/tools/git-dco

# Per-repo install (recommended — keeps the hook visible to teammates)
cd ~/some/repo
git dco init

# Or install globally for all your repos
git dco init --global

# Diagnose
git dco check

# Remove per-repo
git dco uninstall
```

#### What `git dco init` does

1. Writes `.githooks/prepare-commit-msg` in the current repo.
2. Sets `git config --local core.hooksPath .githooks`.
3. From now on, every `git commit` in this repo auto-appends a `Signed-off-by`
   trailer matching `user.email` (DCO requires the trailer email to match the
   commit author email).

#### Local development / testing the formula

```sh
brew install --HEAD --build-from-source ./Formula/git-dco.rb
# or, after tapping a local path:
brew tap jeff-tian/tools "$(pwd)"
brew install --HEAD jeff-tian/tools/git-dco
```

## Releasing a new version

1. Bump `VERSION` in `bin/git-dco`.
2. Bump `version` in `Formula/git-dco.rb`.
3. Tag and push: `git tag v0.1.0 && git push --tags`.
4. (Optional) Switch the formula's `url` from the head-style git URL to a
   release tarball with a pinned `sha256` for reproducible installs.

## License

MIT
