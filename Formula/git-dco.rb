class GitDco < Formula
  desc "One-shot DCO sign-off hook installer for git repositories"
  homepage "https://github.com/Jeff-Tian/homebrew-tools"
  url "https://github.com/Jeff-Tian/homebrew-tools.git",
      branch: "main",
      using:  :git
  version "0.1.0"
  license "MIT"
  head "https://github.com/Jeff-Tian/homebrew-tools.git", branch: "main"

  depends_on "git"

  def install
    bin.install "bin/git-dco"
  end

  test do
    assert_match "git-dco #{version}", shell_output("#{bin}/git-dco --version")

    # `init` should fail cleanly outside a git repo
    output = shell_output("#{bin}/git-dco init 2>&1", 1)
    assert_match "Not inside a git repository", output

    # Inside a fresh repo it should create the hook and set hooksPath
    system "git", "init", "-q", "sample"
    cd "sample" do
      system "git", "config", "user.email", "test@example.com"
      system "git", "config", "user.name", "Tester"
      system bin/"git-dco", "init"
      assert_predicate testpath/"sample/.githooks/prepare-commit-msg", :executable?
      assert_equal ".githooks",
                   shell_output("git config --local core.hooksPath").strip
    end
  end
end
