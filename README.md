# homebrew-tools

Personal Homebrew tap for small developer-workflow tools.

## Install the tap

```sh
brew tap jeff-tian/tools https://github.com/Jeff-Tian/homebrew-tools
```

Once the repo is published as `Jeff-Tian/homebrew-tools` on GitHub, the short
form also works:

```sh
brew tap jeff-tian/tools
```

## Install on Windows

Windows installs are fully automated through Scoop. The Scoop manifests in this
repository download the tool scripts and Windows command wrappers; no manual
copying is required.

```powershell
# If Scoop is not installed yet:
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
iwr -useb get.scoop.sh | iex

# Add this repository as a Scoop bucket:
scoop bucket add jeff-tian-tools https://github.com/Jeff-Tian/homebrew-tools

# Install dependencies and tools:
scoop install git jq curl
scoop install git-auto-commit git-dco
```

After installation, use the tools from PowerShell, Command Prompt, or Git Bash:

```powershell
git auto-commit --version
git dco --version
git dco init
```

`git-auto-commit` can read `$env:GITHUB_TOKEN`; if it is not set, install and
authenticate GitHub CLI (`scoop install gh`, then `gh auth login`) for token
fallback.

## Tools

### `git-auto-commit`

Generate a Conventional / Angular-style commit message from the staged diff
using the GitHub Models API, then commit. Inspired by the `auto-releasenotes`
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

# Preview only:
git auto-commit --dry-run
git auto-commit --print          # message to stdout (CI-friendly)
```

Requires `git`, `curl`, `jq`, and a GitHub token with `models:read`. Reads
`$GITHUB_TOKEN`, falling back to `gh auth token`. The model output language
follows your recent commit history (中文 commits → 中文 message).

#### Scope & ticket auto-detection

The subject is `<type>(<scope>): <subject>` where `<scope>` is a comma-space
separated list. A ticket id matching `[A-Z][A-Z0-9]+-\d+` (e.g. `CNCRM-8729`,
`ABC-123`) is detected from, in priority order:

1. `--ticket=…` flag
2. The current branch name — `feature/CNCRM-8729-jenkins` → `CNCRM-8729`
3. Recent commit messages

The ticket becomes the first item in the scope, followed by any `--scope=`
extras and 1-2 scopes the model infers from the diff. Example:

```
feat(CNCRM-8729, auth, ui): add OAuth login screen
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
| `GIT_AUTO_COMMIT_MODEL` | `openai/gpt-4o-mini` | Model id passed to GitHub Models |
| `GIT_AUTO_COMMIT_API`   | `https://models.github.ai/inference/chat/completions` | Endpoint override |
| `GIT_AUTO_COMMIT_MAX_DIFF` | `12000` | Truncate the staged diff at N chars before sending |
| `GIT_AUTO_COMMIT_TICKET_PATTERN` | `[A-Z][A-Z0-9]+-[0-9]+` | Regex for ticket id detection |

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
