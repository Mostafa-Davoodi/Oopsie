#!/usr/bin/env bash
# Builds a release zip of Oopsie.app and the matching Homebrew cask.
#
# Usage:
#   scripts/release.sh            build build/Oopsie-<version>.zip and build/oopsie.rb
#   scripts/release.sh --publish  also upload the GitHub release and push the cask to the tap
#
# Optional, for a signed and notarized app (no Gatekeeper warning for users):
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE=<profile saved with: xcrun notarytool store-credentials>
#
# Optional overrides:
#   REPO=owner/Oopsie   TAP=owner/homebrew-oopsie
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${REPO:-Mostafa-Davoodi/Oopsie}"
TAP="${TAP:-Mostafa-Davoodi/homebrew-oopsie}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/Oopsie.app"
ZIP="build/Oopsie-$VERSION.zip"
CASK="build/oopsie.rb"

./make-app.sh

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "🔏 Signing with ${DEVELOPER_ID}…"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi

rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "📮 Notarizing…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
fi

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

cat > "$CASK" <<EOF
cask "oopsie" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/Oopsie-#{version}.zip"
  name "Oopsie"
  desc "Menu bar app for disposable Linux machines you can SSH into"
  homepage "https://github.com/$REPO"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"
  depends_on formula: "container"

  app "Oopsie.app"

  uninstall quit: "app.oopsie.Oopsie"

  zap trash: [
    "~/.ssh/oopsie_ed25519",
    "~/.ssh/oopsie_ed25519.pub",
  ]
end
EOF

echo "📦 $ZIP"
echo "   sha256 $SHA"
echo "🍺 $CASK"

if [[ "${1:-}" != "--publish" ]]; then
  echo
  echo "Run again with --publish to upload v$VERSION and update $TAP."
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "✋ Commit your changes first. The release tag must match the code." >&2
  exit 1
fi

OWNER="${REPO%%/*}"
GH_USER="$(gh api user --jq .login)"
if [[ "$GH_USER" != "$OWNER" ]]; then
  echo "✋ gh is logged in as $GH_USER, but the repo belongs to $OWNER." >&2
  echo "   Run: gh auth switch --user $OWNER" >&2
  exit 1
fi

echo "🚀 Publishing v$VERSION to ${REPO}…"
git push origin HEAD
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Oopsie $VERSION" --generate-notes

echo "🍺 Updating ${TAP}…"
TAP_DIR="build/tap"
rm -rf "$TAP_DIR"
gh repo clone "$TAP" "$TAP_DIR"
mkdir -p "$TAP_DIR/Casks"
cp "$CASK" "$TAP_DIR/Casks/oopsie.rb"
git -C "$TAP_DIR" add Casks/oopsie.rb
git -C "$TAP_DIR" commit -m "oopsie $VERSION"
# Push with gh's login, not a GitHub login that the Keychain may hold for another account.
git -C "$TAP_DIR" -c credential.helper= -c credential.helper='!gh auth git-credential' push

echo "✅ Done. Install with: brew install --cask ${TAP%%/*}/${TAP#*/homebrew-}/oopsie"
