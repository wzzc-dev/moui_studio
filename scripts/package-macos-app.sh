#!/usr/bin/env sh
set -eu

# Package a MoUI Studio platform entry as a macOS .app bundle.
# Adapted from the MoUI parent repo scripts/package-macos-app.sh:
# builds with `moon build --release` by default (the parent script pins the
# debug profile) and probes both _build output layouts, because the exe path
# differs between the standalone moui_studio checkout and the MoUI monorepo
# submodule checkout. The parent-only MoonBit manifest validator is not
# available here, so the manifest is written but not validated.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE="macos_skia"
APP_NAME=""
BUNDLE_ID="dev.wzzc.moui.studio"
OUTPUT_DIR="dist/macos"
VERSION="0.1.0"
BUILD_VERSION="1"
PROFILE="release"
SKIP_BUILD=false

usage() {
  printf 'Usage: %s [--package <moon-package>] [--name <app-name>] [--bundle-id <id>] [--version <semver>] [--build-version <build>] [--output <dir>] [--profile release|debug] [--no-build]\n' "$0"
  printf '\n'
  printf 'Builds a native macOS package and wraps the executable in a .app bundle.\n'
  printf 'Example: %s --name "MoUI Studio" --version 0.1.1\n' "$0"
}

xml_text() {
  printf '%s' "$1" | sed -e 's/&/\&/g' -e 's/</\</g' -e 's/>/\>/g'
}

json_text() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      PACKAGE="${2:?missing value for --package}"
      shift 2
      ;;
    --name)
      APP_NAME="${2:?missing value for --name}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:?missing value for --bundle-id}"
      shift 2
      ;;
    --version)
      VERSION="${2:?missing value for --version}"
      shift 2
      ;;
    --build-version)
      BUILD_VERSION="${2:?missing value for --build-version}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:?missing value for --output}"
      shift 2
      ;;
    --profile)
      PROFILE="${2:?missing value for --profile}"
      shift 2
      ;;
    --no-build)
      SKIP_BUILD=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$PROFILE" in
  release|debug) ;;
  *)
    printf 'Unsupported profile: %s (expected release|debug)\n' "$PROFILE" >&2
    exit 2
    ;;
esac

PACKAGE_LEAF="$(basename "$PACKAGE")"
if [ -z "$APP_NAME" ]; then
  APP_NAME="MoUI Studio"
fi

# The exe lands under build/<package-path>/ in a standalone checkout and under
# build/<module-name>/<package-path>/ inside the MoUI workspace; probe both.
EXE_PATH="_build/native/$PROFILE/build/$PACKAGE/$PACKAGE_LEAF.exe"
if [ ! -f "$EXE_PATH" ]; then
  EXE_PATH="_build/native/$PROFILE/build/wzzc-dev/moui_studio/$PACKAGE/$PACKAGE_LEAF.exe"
fi
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_EXE="$MACOS_DIR/$PACKAGE_LEAF"
MANIFEST_PATH="$RESOURCES_DIR/moui-package.json"

if [ "$SKIP_BUILD" = false ]; then
  printf '==> Building %s (profile: %s)\n' "$PACKAGE" "$PROFILE"
  if [ "$PROFILE" = "release" ]; then
    moon build "$PACKAGE" --target native --release
  else
    moon build "$PACKAGE" --target native
  fi
fi

if [ ! -f "$EXE_PATH" ]; then
  printf 'Built executable not found: %s\n' "$EXE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXE_PATH" "$APP_EXE"
chmod +x "$APP_EXE"

PLIST_EXECUTABLE="$(xml_text "$PACKAGE_LEAF")"
PLIST_BUNDLE_ID="$(xml_text "$BUNDLE_ID")"
PLIST_APP_NAME="$(xml_text "$APP_NAME")"
PLIST_VERSION="$(xml_text "$VERSION")"
PLIST_BUILD_VERSION="$(xml_text "$BUILD_VERSION")"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PLIST_EXECUTABLE</string>
  <key>CFBundleIdentifier</key>
  <string>$PLIST_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$PLIST_APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$PLIST_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$PLIST_BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

JSON_APP_NAME="$(json_text "$APP_NAME")"
JSON_PACKAGE="$(json_text "$PACKAGE")"
JSON_BUNDLE_ID="$(json_text "$BUNDLE_ID")"
JSON_VERSION="$(json_text "$VERSION")"
JSON_BUILD_VERSION="$(json_text "$BUILD_VERSION")"
JSON_EXECUTABLE="$(json_text "$PACKAGE_LEAF")"
JSON_BUNDLE="$(json_text "$APP_NAME.app")"
JSON_PROFILE="$(json_text "$PROFILE")"

cat > "$MANIFEST_PATH" <<EOF
{
  "schemaVersion": 1,
  "platform": "macos",
  "outputKind": "app-bundle",
  "appName": "$JSON_APP_NAME",
  "moonPackage": "$JSON_PACKAGE",
  "bundleIdentifier": "$JSON_BUNDLE_ID",
  "version": "$JSON_VERSION",
  "buildNumber": "$JSON_BUILD_VERSION",
  "profile": "$JSON_PROFILE",
  "executable": "$JSON_EXECUTABLE",
  "bundleName": "$JSON_BUNDLE",
  "runtimeFiles": []
}
EOF

printf '==> Wrote %s\n' "$APP_DIR"
