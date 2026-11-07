class GitDco < Formula
  desc "One-shot DCO sign-off hook installer for git repositories"
  homepage "https://github.com/Jeff-Tian/homebrew-tools"
  url "https://github.com/Jeff-Tian/homebrew-tools.git",
      branch: "main",
      using:  :git
  version "0.1.1"
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

    # A fresh repo uses Git's hooks directory without changing configuration.
    system "git", "init", "-q", "sample"
    cd "sample" do
      system "git", "config", "user.email", "test@example.com"
      system "git", "config", "user.name", "Tester"
      system bin/"git-dco", "init"
      assert_predicate testpath/"sample/.git/hooks/prepare-commit-msg", :executable?
      assert_empty shell_output("git config --local --get core.hooksPath", 1)
    end
  end
end
