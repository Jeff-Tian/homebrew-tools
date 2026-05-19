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

## Tools

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
