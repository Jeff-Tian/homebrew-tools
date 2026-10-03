class GitAutoCommit < Formula
  desc "Generate Conventional commit messages with gitmoji emoji from staged diff"
  homepage "https://github.com/Jeff-Tian/homebrew-tools"
  url "https://github.com/Jeff-Tian/homebrew-tools.git",
      branch: "main",
      using:  :git
  version "0.4.0"
  license "MIT"
  head "https://github.com/Jeff-Tian/homebrew-tools.git", branch: "main"

  depends_on "git"

  def install
    json = File.read(File.join(__dir__, "../bucket/git-auto-commit.json"))
    v = JSON.parse(json)["version"]

    # Source scripts from the tap directory rather than the formula's URL
    # source tree. The `url` tracks `main`, so during PR CI the source tree
    # lacks files that only exist on the PR branch; the tap is the checked-out
    # PR branch (and the main repo for end users), so it always has them.
    # Copy into the build dir so Homebrew's sandbox can install them.
    tap_bin = File.expand_path("../bin", __dir__)
    cp "#{tap_bin}/git-auto-commit", "bin/git-auto-commit"
    cp "#{tap_bin}/git-auto-commit-ai.rb", "bin/git-auto-commit-ai.rb"
    if File.exist?("#{tap_bin}/gitmojis.txt")
      cp "#{tap_bin}/gitmojis.txt", "bin/gitmojis.txt"
    end

    # Inject version into the script at install time so --version works
    # after brew install (when ../bucket/ is no longer on PATH).
    inreplace "bin/git-auto-commit",
              'VERSION="${GIT_AUTO_COMMIT_VERSION:-}"',
              "VERSION=\"#{v}\""
    bin.install "bin/git-auto-commit"
    bin.install "bin/git-auto-commit-ai.rb"
    if File.exist?("bin/gitmojis.txt")
      bin.install "bin/gitmojis.txt"
    end
  end

  test do
    assert_match "git-auto-commit #{version}",
                 shell_output("#{bin}/git-auto-commit --version")

    assert_predicate bin/"git-auto-commit-ai.rb", :executable?

    # Outside a git repo it should fail cleanly before invoking Copilot CLI.
    output = shell_output("#{bin}/git-auto-commit --dry-run 2>&1", 1)
    assert_match(/Not inside a git repository|Nothing staged/, output)

    # Verify the packaged executable resolves its Brickverse helper.
    output = shell_output("#{bin}/git-auto-commit --backend=brickverse --dry-run 2>&1", 1)
    assert_match "Not inside a git repository", output
  end
end
