class Id6MailMcp < Formula
  desc "Read-only Outlook mail search MCP server for AI agents, via id6"
  homepage "https://github.com/Jeff-Tian/id6-mail-mcp"
  url "https://api.nuget.org/v3-flatcontainer/jefftian.id6mail.mcp/0.1.0/jefftian.id6mail.mcp.0.1.0.nupkg",
      using: :nounzip
  version "0.1.0"
  sha256 "33102f2fa7d6804a0ed3888fe8e1d1e22a49848a417b06e958333a2662e49e8b"
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
end
