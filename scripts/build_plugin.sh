#!/usr/bin/env sh
set -eu

# Build a WASM plugin artifact for the MoUI Studio plugin system.
#
# Plugins use the **standard C ABI** for strings (UTF-8 bytes + explicit
# length), because MoonBit's `wasm` target represents `String` as a GC
# reference that a foreign host cannot construct. The reference plugin is
# therefore written in Rust and compiled to `wasm32-unknown-unknown`.
#
# The host calls the plugin like this:
#
#   studio_describe()                      -> contribution JSON
#   studio_call(ptr, len)                  -> response length
#   studio_last_result_len()               -> response byte length
#   studio_set_response_ptr(base)          -> tell the plugin where the
#                                             response area lives
#
# Usage:
#   scripts/build_plugin.sh [package-dir] [output-dir]
#
# Defaults: package-dir = samples/plugin_fixture, output-dir = the package's
# own `dist/` directory.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_DIR="${1:-samples/plugin_fixture}"
OUTPUT_DIR="${2:-$PACKAGE_DIR/dist}"

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not found (install Rust: https://rustup.rs)" >&2
  exit 2
fi

if ! rustup target list --installed 2>/dev/null | grep -q wasm32-unknown-unknown; then
  echo "adding rust target wasm32-unknown-unknown..."
  rustup target add wasm32-unknown-unknown
fi

echo "building ${PACKAGE_DIR} (rust, wasm32-unknown-unknown)..."
cargo build \
  --manifest-path "$PACKAGE_DIR/Cargo.toml" \
  --target wasm32-unknown-unknown \
  --release

WASM_FILE="$PACKAGE_DIR/target/wasm32-unknown-unknown/release/plugin_fixture.wasm"
if [ ! -f "$WASM_FILE" ]; then
  echo "expected wasm artifact not found: ${WASM_FILE}" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/plugin_fixture.wasm"
cp "$WASM_FILE" "$OUTPUT_FILE"
echo "wrote ${OUTPUT_FILE}"
