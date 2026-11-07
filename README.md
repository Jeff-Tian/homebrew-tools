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

## Install the Brickverse font

This tap also ships a [Homebrew Cask](https://docs.brew.sh/Cask-Cookbook)
for the [Brickverse](https://font.brickverse.net/) font family (OFL 1.1
licensed). It installs all eight static TTFs (Regular, Italic, Medium,
MediumItalic, SemiBold, SemiBoldItalic, Bold, BoldItalic) into your user
fonts directory.

```sh
brew install --cask jeff-tian/tools/font-brickverse
```

Or, once the tap is installed, the short form works too:

```sh
brew install --cask font-brickverse
```

The cask uses `version :latest` because the download URL always points at
the newest build. Run the following any time you want the latest fonts:

```sh
brew upgrade --cask font-brickverse
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
  `$XDG_CACHE_HOME/brickverse/cf_authorization` when `XDG_CACHE_HOME` is non-empty, or
  `~/.cache/brickverse/cf_authorization` otherwise. Requires Ruby. Significantly faster than Copilot CLI
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
git auto-commit --no-gitmoji                # opt out of gitmoji emoji prefix

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

The subject is `<emoji> <type>(<scope>): <subject>` where `<scope>` is a comma-space
separated list. A ticket id matching `[A-Z][A-Z0-9]+-[0-9]+` (e.g. `ABC-123`)
or a GitHub issue reference matching `#[0-9]+` (e.g. `#1988`)
is detected from, in priority order:

1. `--ticket=…` flag
2. The current branch name — `feature/ABC-123-some-desc` → `ABC-123`
3. Recent commit messages

The ticket becomes the first item in the scope, followed by any `--scope=`
extras and 1-2 scopes the model infers from the diff. Example:

```
✨ feat(ABC-123, auth, ui): add OAuth login screen
```

Pass `--no-ticket` to disable, or set `GIT_AUTO_COMMIT_TICKET_PATTERN` to a
custom regex (e.g. for `JIRA_1234`-style ids). GitHub issue references are
supported by default, producing subjects such as `fix(#1988, cli): handle errors`.

#### Gitmoji

By default `git auto-commit` prepends a [gitmoji](https://github.com/carloscuesta/gitmoji)
emoji to the commit message, chosen by the commit type:

```
✨ feat(auth): add OAuth login
🐛 fix(api): handle null response
📝 docs(readme): update install guide
```

The emoji mapping is bundled with the tool (in `bin/gitmojis.txt`).
Installations receive the bundled mapping; pass `--no-gitmoji` to disable
the emoji prefix and get plain Conventional Commits:

```
feat(auth): add OAuth login
```

To refresh the gitmoji mapping manually (e.g. after upstream adds new emojis):

```sh
./scripts/update-gitmoji.sh
```

The script fetches the latest data from
[`carloscuesta/gitmoji`](https://raw.githubusercontent.com/carloscuesta/gitmoji/master/packages/gitmojis/src/gitmojis.json)
and regenerates `bin/gitmojis.txt`.

#### DCO sign-off

By default `git auto-commit` runs `git commit -s`, appending a
`Signed-off-by: Your Name <you@example.com>` trailer so the GitHub DCO check
passes. This is idempotent and safe to combine with the [`git dco`](#git-dco)
hook — git won't add a duplicate trailer. Pass `--no-sign-off` to opt out.

Environment overrides:

| Variable | Default | Purpose |
|---|---|---|
| `GIT_AUTO_COMMIT_TICKET_PATTERN` | `([A-Z][A-Z0-9]+-[0-9]+\|#[0-9]+)` | Regex for ticket id detection |
| `GIT_AUTO_COMMIT_BACKEND` | `copilot` | AI backend: `copilot` (Copilot CLI) or `brickverse` (Cloudflare Workers AI) |
| `AI_MODEL` | `auto` (copilot)<br>`llama-3.3-70b` (brickverse) | Model name for `git auto-commit`; `--model` takes precedence. |
| `GIT_AUTO_COMMIT_MAX_DIFF` | `12000` | Truncate the staged diff at N chars before sending. |
| `BRICKVERSE_HOST` | `https://pub.brickverse.net` | (brickverse backend only) Override the model-proxy origin |

### `git-dco`

One-shot DCO sign-off hook installer. Adds a `prepare-commit-msg` hook that
appends `Signed-off-by:` to every commit so GitHub's DCO check passes without
having to remember `git commit -s`.

```sh
brew install jeff-tian/tools/git-dco

# Per-repo install (recommended)
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

1. Wraps `prepare-commit-msg` in the active hooks directory, preserving any
   existing hook in a sibling `.git-dco-original` file and running it first.
2. Leaves `core.hooksPath` and all other hooks unchanged. With no configuration,
   Git's own hooks directory is used; existing `.githooks` installs keep working.
3. From now on, every `git commit` in this repo auto-appends a `Signed-off-by`
   trailer matching `user.email` (DCO requires the trailer email to match the
   commit author email).

Installation is idempotent, including upgrades from the unmodified 0.1.0 hook.
Uninstall restores the original hook without unsetting `core.hooksPath`; it
refuses to overwrite later edits. Per-repo installation refuses inherited
global/system hooks paths to avoid affecting other repositories.
`init --global` explicitly installs globally, preserving an existing absolute
global hooks path (or choosing `~/.githooks` if unset).

#### Local development / testing the formula

```sh
brew install --HEAD --build-from-source ./Formula/git-dco.rb
# or, after tapping a local path:
brew tap jeff-tian/tools "$(pwd)"
brew install --HEAD jeff-tian/tools/git-dco
```

### `git-agent-guard`

One-shot installer that blocks agent-initiated commits and pushes without
disabling existing formatting, DCO or other Git hooks.

```sh
brew install jeff-tian/tools/git-agent-guard

cd ~/some/repo
git agent-guard init
git agent-guard check

# Restore the original hooks when no longer needed.
git agent-guard uninstall
```

`init` wraps `pre-commit` and `pre-push` in the active hooks directory. It does
not change `core.hooksPath`; with no configuration, Git's own hooks directory
is used. Existing hooks are moved to sibling `.git-agent-guard-original`
files and run after the guard, preserving their arguments, stdin and exit
status. `prepare-commit-msg` (including the DCO hook) is left untouched.
Repeated installation is safe; uninstall restores the original hooks and
refuses to overwrite later edits.

With git-dco 0.1.1 or newer, `git dco init` and `git agent-guard init` can run
in either order; repeated installs and uninstalling one leave the other intact.
Changing `core.hooksPath` manually (or configuring a global path) still selects
another directory: rerun both checks after such changes. Inherited global or
system hooks paths are not modified by per-repo installation; choose a
repository-local hooks directory, preserving your existing hooks, first.

The guard detects nonempty `AI_AGENT` or `COPILOT_AGENT_SESSION_ID`.
Human terminals without those markers are unaffected. Agent launchers must
set a marker; unmarked agents cannot be detected. This is an accident guard,
not a security boundary: repository agent instructions must also prohibit
`--no-verify`, clearing markers and modifying hooks to bypass it.

Installation is per repository/machine and must be repeated after cloning;
it does not run automatically during `brew install` or `git clone`.
Only Homebrew packaging is provided for this tool, not Scoop.

## Running tests

From the repository root, run the `git-auto-commit` tests with Bash:

```bash
bash tests/git-auto-commit.sh
bash tests/git-agent-guard.sh
bash tests/git-dco.sh
```

With RTK installed, the equivalent command is:

```bash
rtk proxy bash tests/git-auto-commit.sh
```

Do not use `sh tests/git-auto-commit.sh`: explicitly invoking `sh` ignores the
script's Bash shebang. Different shell variable-scoping behavior can leak mock
values between test cases and cause failures. The tests use a temporary Git
repository and a mock Copilot CLI; no Copilot login or AI requests are needed.

## Releasing a new version

1. Bump `VERSION` in `bin/git-dco`.
2. Bump `version` in `Formula/git-dco.rb`.
3. Tag and push: `git tag v0.1.0 && git push --tags`.
4. (Optional) Switch the formula's `url` from the head-style git URL to a
   release tarball with a pinned `sha256` for reproducible installs.

## License

MIT
