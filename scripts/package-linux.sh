#!/usr/bin/env sh
set -eu

# Build the MoUI Studio Linux Skia entry and pack the executable into a
# tar.gz. The binary links the pinned static Skia release and the system
# Wayland/X11 client libraries; RUNTIME-DEPENDENCIES.txt in the archive lists
# what a user machine needs to run it.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE="linux_skia"
OUTPUT_DIR="dist/linux"
VERSION="0.1.0"
PROFILE="release"
SKIP_BUILD=false

usage() {
  printf 'Usage: %s [--package <moon-package>] [--version <semver>] [--output <dir>] [--profile release|debug] [--no-build]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --package)
      PACKAGE="${2:?missing value for --package}"
      shift 2
      ;;
    --version)
      VERSION="${2:?missing value for --version}"
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

if [ "$SKIP_BUILD" = false ]; then
  printf '==> Building %s (profile: %s)\n' "$PACKAGE" "$PROFILE"
  if [ "$PROFILE" = "release" ]; then
    moon build "$PACKAGE" --target native --release
  else
    moon build "$PACKAGE" --target native
  fi
fi

# The exe lands under build/<package-path>/ in a standalone checkout and under
# build/<module-name>/<package-path>/ inside the MoUI workspace; probe both
# after the build.
EXE_PATH="_build/native/$PROFILE/build/$PACKAGE/$PACKAGE_LEAF.exe"
if [ ! -f "$EXE_PATH" ]; then
  EXE_PATH="_build/native/$PROFILE/build/wzzc-dev/moui_studio/$PACKAGE/$PACKAGE_LEAF.exe"
fi

if [ ! -f "$EXE_PATH" ]; then
  printf 'Built executable not found: %s\n' "$EXE_PATH" >&2
  exit 1
fi

STAGE_DIR="$OUTPUT_DIR/moui-studio-linux"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp "$EXE_PATH" "$STAGE_DIR/moui-studio"
chmod +x "$STAGE_DIR/moui-studio"

cat > "$STAGE_DIR/RUNTIME-DEPENDENCIES.txt" <<'EOF'
MoUI Studio (Linux) runtime dependencies
========================================

The bundled binary statically links the pinned Skia release; it dynamically
links the desktop platform libraries below. On Debian/Ubuntu:

  sudo apt-get install -y \
    libwayland-client0 libx11-6 libxext6 libxrandr2 \
    libfontconfig1 libfreetype6

Run:

  ./moui-studio

The app opens a native Wayland (or X11) window.
EOF

ARCH="$(uname -m)"
TAR_PATH="$OUTPUT_DIR/moui-studio-linux-$ARCH-$VERSION.tar.gz"
rm -f "$TAR_PATH"
tar -czf "$TAR_PATH" -C "$STAGE_DIR" .
printf '==> Wrote %s\n' "$TAR_PATH"
