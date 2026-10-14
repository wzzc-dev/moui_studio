#!/usr/bin/env sh
set -eu

# Assemble a servable MoUI Studio Web bundle and zip it.
#
# web_wasm/index.html resolves its ES-module runtime relative to the checkout
# root (`../.mooncakes/...`) and probes several `_build/wasm-gc/...` layouts
# for the wasm module, so the bundle mirrors the checkout root: web_wasm/ +
# .mooncakes/ + _build/. Serve the unzipped root with any static file server
# and open /web_wasm/.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="dist/web"
VERSION="0.1.0"
PROFILE="release"
SKIP_BUILD=false

usage() {
  printf 'Usage: %s [--version <semver>] [--output <dir>] [--profile release|debug] [--no-build]\n' "$0"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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

BUNDLE_DIR="$OUTPUT_DIR/moui-studio-web"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

if [ "$SKIP_BUILD" = false ]; then
  printf '==> Building web_wasm (profile: %s)\n' "$PROFILE"
  if [ "$PROFILE" = "release" ]; then
    moon build web_wasm --target wasm-gc --release
  else
    moon build web_wasm --target wasm-gc
  fi
fi

# 1) The static entry page.
cp web_wasm/index.html "$BUNDLE_DIR/index.html"

# 2) The ES-module runtimes: moui_web_renderer's runtime.js (+ its Canvas2D
#    fallback, loaded on demand) and moui's browser_runtime.js, at the exact
#    relative paths the imports expect under .mooncakes/.
RUNTIME_DIR="$BUNDLE_DIR/.mooncakes/wzzc-dev"
mkdir -p "$RUNTIME_DIR/moui_web_renderer/canvas2d" "$RUNTIME_DIR/moui/backend/web"
for js in runtime.js canvas2d_runtime.js; do
  if [ -f ".mooncakes/wzzc-dev/moui_web_renderer/$js" ]; then
    cp ".mooncakes/wzzc-dev/moui_web_renderer/$js" "$RUNTIME_DIR/moui_web_renderer/$js"
  elif [ -f "../moui_web_renderer/$js" ]; then
    cp "../moui_web_renderer/$js" "$RUNTIME_DIR/moui_web_renderer/$js"
  else
    printf 'Missing web runtime asset: %s\n' "$js" >&2
    exit 1
  fi
done
if [ -f ".mooncakes/wzzc-dev/moui_web_renderer/canvas2d/canvas2d_runtime.js" ]; then
  cp .mooncakes/wzzc-dev/moui_web_renderer/canvas2d/canvas2d_runtime.js \
    "$RUNTIME_DIR/moui_web_renderer/canvas2d/canvas2d_runtime.js"
elif [ -f "../moui_web_renderer/canvas2d/canvas2d_runtime.js" ]; then
  cp ../moui_web_renderer/canvas2d/canvas2d_runtime.js \
    "$RUNTIME_DIR/moui_web_renderer/canvas2d/canvas2d_runtime.js"
fi
if [ -f ".mooncakes/wzzc-dev/moui/backend/web/browser_runtime.js" ]; then
  cp .mooncakes/wzzc-dev/moui/backend/web/browser_runtime.js \
    "$RUNTIME_DIR/moui/backend/web/browser_runtime.js"
else
  printf 'Missing web runtime asset: browser_runtime.js\n' >&2
  exit 1
fi

# 3) The wasm module. In a standalone checkout it lands under
#    build/web_wasm/, inside the MoUI workspace under
#    build/wzzc-dev/moui_studio/web_wasm/; copy it to wherever it was found,
#    keeping the _build prefix so index.html's probes resolve.
WASM=""
for candidate in \
  "_build/wasm-gc/$PROFILE/build/web_wasm/web_wasm.wasm" \
  "_build/wasm-gc/$PROFILE/build/wzzc-dev/moui_studio/web_wasm/web_wasm.wasm"; do
  if [ -f "$candidate" ]; then
    WASM="$candidate"
    break
  fi
done
if [ -z "$WASM" ]; then
  printf 'Built wasm module not found under _build/wasm-gc/%s\n' "$PROFILE" >&2
  exit 1
fi
mkdir -p "$BUNDLE_DIR/$(dirname "$WASM")"
cp "$WASM" "$BUNDLE_DIR/$WASM"

ZIP_PATH="$OUTPUT_DIR/moui-studio-web-$VERSION.zip"
rm -f "$ZIP_PATH"
(cd "$BUNDLE_DIR" && zip -qr "$OLDPWD/$ZIP_PATH" .)
printf '==> Wrote %s\n' "$ZIP_PATH"
