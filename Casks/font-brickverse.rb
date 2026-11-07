cask "font-brickverse" do
  version :latest
  sha256 :no_check

  url "https://font.brickverse.net/downloads/Brickverse-ttfs.zip"
  name "Brickverse"
  desc "Humanist sans variable font (wght 400-700) with matching italics, OFL licensed"
  homepage "https://font.brickverse.net/"

  # The download URL is rebuilt and redeployed on every push to GlyphForge main,
  # so it always points at the latest build. `version :latest` makes
  # `brew upgrade --cask font-brickverse` re-download the current fonts.
  font "Brickverse-Bold.ttf"
  font "Brickverse-BoldItalic.ttf"
  font "Brickverse-Italic.ttf"
  font "Brickverse-Medium.ttf"
  font "Brickverse-MediumItalic.ttf"
  font "Brickverse-Regular.ttf"
  font "Brickverse-SemiBold.ttf"
  font "Brickverse-SemiBoldItalic.ttf"

  caveats <<~EOS
    Brickverse is OFL 1.1 licensed. The variable fonts (Brickverse[wght].ttf and
    Brickverse-Italic[wght].ttf) are also available from
    https://font.brickverse.net/downloads
  EOS
end
