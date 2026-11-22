class Id6MailMcp < Formula
  desc "Read-only Outlook mail search MCP server for AI agents, via id6"
  homepage "https://github.com/Jeff-Tian/id6-mail-mcp"
  url "https://api.nuget.org/v3-flatcontainer/jefftian.id6mail.mcp/0.2.0/jefftian.id6mail.mcp.0.2.0.nupkg",
      using: :nounzip
  version "0.2.0"
  sha256 "eb9d11fbea8f5ad34b909bb8b7f9b97315f8b51e1aac59d8350f49005a09a41a"
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
    run "id6-mail-mcp",
        base: :libexec,
        args: ["setup", "--command", "#{HOMEBREW_PREFIX}/opt/id6-mail-mcp/bin/id6-mail-mcp"],
        must_succeed: false
  end
end
