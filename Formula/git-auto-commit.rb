class GitAutoCommit < Formula
  desc "Generate Conventional/Angular commit messages from staged diff via AI"
  homepage "https://github.com/Jeff-Tian/homebrew-tools"
  url "https://github.com/Jeff-Tian/homebrew-tools.git",
      branch: "main",
      using:  :git
  version "0.2.4"
  license "MIT"
  head "https://github.com/Jeff-Tian/homebrew-tools.git", branch: "main"

  depends_on "curl"
  depends_on "git"
  depends_on "jq"

  def install
    json = File.read(File.join(__dir__, "../bucket/git-auto-commit.json"))
    v = JSON.parse(json)["version"]
    # Inject version into the script at install time so --version works
    # after brew install (when ../bucket/ is no longer on PATH).
    inreplace "bin/git-auto-commit",
              'VERSION="${GIT_AUTO_COMMIT_VERSION:-}"',
              "VERSION=\"#{v}\""
    bin.install "bin/git-auto-commit"
  end

  test do
    assert_match "git-auto-commit #{version}",
                 shell_output("#{bin}/git-auto-commit --version")

    # Outside a git repo it should fail cleanly (note: no token needed to reach that check).
    ENV["GITHUB_TOKEN"] = "dummy"
    output = shell_output("#{bin}/git-auto-commit --dry-run 2>&1", 1)
    assert_match(/Not inside a git repository|Nothing staged/, output)
  end
end
