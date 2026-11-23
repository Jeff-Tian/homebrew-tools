class Id6MailMcp < Formula
  desc "Read-only Outlook mail search MCP server for AI agents, via id6"
  homepage "https://github.com/Jeff-Tian/id6-mail-mcp"
  url "https://api.nuget.org/v3-flatcontainer/jefftian.id6mail.mcp/0.4.0/jefftian.id6mail.mcp.0.4.0.nupkg",
      using: :nounzip
  version "0.4.0"
  sha256 "85a213aff4c426a24c04329751086e2ecd0ebaaf386ec46c03be5d8f50fd7815"
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
