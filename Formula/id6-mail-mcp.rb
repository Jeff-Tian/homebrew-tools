class Id6MailMcp < Formula
  desc "Read-only Outlook mail search MCP server for AI agents, via id6"
  homepage "https://github.com/Jeff-Tian/id6-mail-mcp"
  url "https://api.nuget.org/v3-flatcontainer/jefftian.id6mail.mcp/0.2.2/jefftian.id6mail.mcp.0.2.2.nupkg",
      using: :nounzip
  version "0.2.2"
  sha256 "c49b8cf250de96195c766a9bd20aa2f5665ac51f0b4a42b85bd6418c1c313f9f"
  license "MIT"

  depends_on "dotnet"

  def install
    system "dotnet", "tool", "install",
           "--tool-path", libexec,
           "--add-source", buildpath,
           "--version", version.to_s,
           "JeffTian.Id6Mail.Mcp"
    bin.install_symlink libexec/"id6-mail-mcp"
  end

  test do
    assert_path_exists bin/"id6-mail-mcp"
  end

  post_install_steps do
    # `run` gives the step a closed stdin, so reattach it to the terminal for the prompt.
    run "/bin/sh",
        args: ["-c", "exec #{HOMEBREW_PREFIX}/opt/id6-mail-mcp/bin/id6-mail-mcp setup " \
                     "--command #{HOMEBREW_PREFIX}/opt/id6-mail-mcp/bin/id6-mail-mcp < /dev/tty"],
        must_succeed: false
  end
end
