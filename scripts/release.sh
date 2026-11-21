#!/usr/bin/env bash
# Builds a release: the app, a DMG, release notes and a signed Sparkle appcast. Run from the repo root:
#   ./scripts/release.sh 0.1.1
#
# Before running:
#   - CHANGELOG.md has a "## 0.1.1" section (its text becomes the release notes shown in the update window).
#   - The Sparkle signing key is in this Mac's login Keychain (created once with Sparkle's generate_keys).
#
# It publishes nothing. It prints the tag and the files to upload to a GitHub release named v<version>.
# The app is not signed with a Developer ID or notarised, so testers confirm it once in
# System Settings → Privacy & Security → Open Anyway. Updates installed by Sparkle need no such step.
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Usage: $0 <version>, for example $0 0.1.1" >&2
  exit 1
fi

APP_NAME="CraftPeep"
PROJECT="App/${APP_NAME}/${APP_NAME}.xcodeproj"
REPO_URL="https://github.com/kollol-dev/craftpeep"
# Overridable for a local update test against a feed served from this Mac.
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-${REPO_URL}/releases/download/v${VERSION}/}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
DIST="${DIST:-dist}"
DERIVED="build-release"
OUT="${DIST}/${VERSION}"
DMG="${OUT}/${APP_NAME}-${VERSION}.dmg"
# Sparkle compares CFBundleVersion, so it must only ever go up. The commit count does.
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

if [ ! -d "$PROJECT" ]; then
  echo "Project not found at $PROJECT. Run this script from the repo root." >&2
  exit 1
fi
if ! grep -qE "^## ${VERSION}( |$)" "$CHANGELOG"; then
  echo "$CHANGELOG has no '## ${VERSION}' section. Add one; it becomes the release notes." >&2
  exit 1
fi
if [ -n "$(git status --porcelain)" ]; then
  echo "Warning: the working tree has uncommitted changes; the release will include them." >&2
fi
if [ -e "$OUT" ]; then
  echo "$OUT already exists. Remove it to rebuild this version." >&2
  exit 1
fi

echo "==> Building ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER})"
xcodebuild -project "$PROJECT" -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build | grep -E '^(\*\*|error:)' || true

APP_PATH="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
SPARKLE_BIN="${DERIVED}/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [ ! -d "$APP_PATH" ]; then
  echo "Build failed: $APP_PATH not found." >&2
  exit 1
fi
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  echo "Built app reports version $BUILT_VERSION, expected $VERSION." >&2
  exit 1
fi

echo "==> Creating DMG"
mkdir -p "$OUT"
STAGING="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "${APP_NAME} ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "==> Writing release notes"
# Sparkle picks up an .html file with the same name as the archive and embeds it in the appcast.
python3 -I - "$VERSION" "$CHANGELOG" "${OUT}/${APP_NAME}-${VERSION}.html" <<'PY'
import html, re, sys
version, changelog, out = sys.argv[1:4]
lines, take = [], False
for line in open(changelog, encoding="utf-8"):
    if line.startswith("## "):
        if take:
            break
        take = re.match(rf"## {re.escape(version)}\b", line) is not None
        continue
    if take:
        lines.append(line.rstrip("\n"))
parts, in_list = [], False
def inline(text):
    text = html.escape(text)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
for line in lines:
    if line.startswith("- "):
        if not in_list:
            parts.append("<ul>"); in_list = True
        parts.append(f"<li>{inline(line[2:])}</li>")
        continue
    if in_list and line.strip() == "":
        continue
    if in_list:
        parts.append("</ul>"); in_list = False
    if line.startswith("### "):
        parts.append(f"<h3>{inline(line[4:])}</h3>")
    elif line.strip():
        parts.append(f"<p>{inline(line)}</p>")
if in_list:
    parts.append("</ul>")
open(out, "w", encoding="utf-8").write("\n".join(parts) + "\n")
PY

echo "==> Signing and writing the appcast"
# Reads the private EdDSA key from the login Keychain; macOS may ask to allow access.
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --embed-release-notes \
  --maximum-versions 1 \
  -o "${OUT}/appcast.xml" \
  "$OUT"

echo
echo "==> Done. Files in ${OUT}:"
ls -1 "$OUT"
cat <<EOF

To publish:
  1. git tag v${VERSION} && git push origin v${VERSION}
  2. On ${REPO_URL}/releases/new choose tag v${VERSION}, title "${APP_NAME} ${VERSION}",
     paste the ${VERSION} notes from CHANGELOG.md, and attach:
       ${DMG}
       ${OUT}/appcast.xml
  3. Publish it as the latest release (not a pre-release, or the feed URL will not point at it).

Installed copies find the update within a day, or at once with ${APP_NAME} → Check for Updates….
EOF
