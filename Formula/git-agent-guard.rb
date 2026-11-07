class GitAgentGuard < Formula
  desc "One-shot installer blocking agent commits and pushes while preserving Git hooks"
  homepage "https://github.com/Jeff-Tian/homebrew-tools"
  url "https://github.com/Jeff-Tian/homebrew-tools.git",
      branch: "main",
      using:  :git
  version "0.1.0"
  license "MIT"
  head "https://github.com/Jeff-Tian/homebrew-tools.git", branch: "main"

  depends_on "git"

  def install
    bin.install "bin/git-agent-guard"
  end

  test do
    assert_match "git-agent-guard #{version}", shell_output("#{bin}/git-agent-guard --version")
    assert_match "Not inside a git repository", shell_output("#{bin}/git-agent-guard init 2>&1", 1)

    system "git", "init", "-q", "sample"
    cd "sample" do
      system bin/"git-agent-guard", "init"
      system bin/"git-agent-guard", "check"
      assert_predicate testpath/"sample/.git/hooks/pre-commit", :executable?
      assert_predicate testpath/"sample/.git/hooks/pre-push", :executable?
      assert_match "AI agent session",
                   shell_output("AI_AGENT=test .git/hooks/pre-push 2>&1", 1)
      system bin/"git-agent-guard", "uninstall"
      refute_path_exists testpath/"sample/.git/hooks/pre-push"
    end
  end
end
