class Id6MailMcp < Formula
  desc "Read-only Outlook mail search MCP server for AI agents, via id6"
  homepage "https://github.com/Jeff-Tian/id6-mail-mcp"
  url "https://api.nuget.org/v3-flatcontainer/jefftian.id6mail.mcp/0.2.1/jefftian.id6mail.mcp.0.2.1.nupkg",
      using: :nounzip
  version "0.2.1"
  sha256 "83fca92d36ae8b5ccbd6d31d020ba67b39b906dea28cc76c8aec98f0b7359a4a"
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
