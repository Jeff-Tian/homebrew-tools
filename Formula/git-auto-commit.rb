class GitAutoCommit < Formula
  desc "Generate Conventional commit messages with gitmoji emoji from staged diff"
  homepage "https://github.com/Jeff-Tian/homebrew-tools"
  url "https://github.com/Jeff-Tian/homebrew-tools.git",
      branch: "main",
      using:  :git
  version "0.2.8"
  license "MIT"
  head "https://github.com/Jeff-Tian/homebrew-tools.git", branch: "main"

  depends_on "git"

  def install
    json = File.read(File.join(__dir__, "../bucket/git-auto-commit.json"))
    v = JSON.parse(json)["version"]
    # Inject version into the script at install time so --version works
    # after brew install (when ../bucket/ is no longer on PATH).
    inreplace "bin/git-auto-commit",
              'VERSION="${GIT_AUTO_COMMIT_VERSION:-}"',
              "VERSION=\"#{v}\""
    bin.install "bin/git-auto-commit"
    if File.exist?("bin/gitmojis.txt")
      bin.install "bin/gitmojis.txt"
    end
  end

  test do
    assert_match "git-auto-commit #{version}",
                 shell_output("#{bin}/git-auto-commit --version")

    # Outside a git repo it should fail cleanly before invoking Copilot CLI.
    output = shell_output("#{bin}/git-auto-commit --dry-run 2>&1", 1)
    assert_match(/Not inside a git repository|Nothing staged/, output)
  end
end
