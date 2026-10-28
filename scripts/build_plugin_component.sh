#!/usr/bin/env sh
set -eu

# 构建「组件形态」的参考插件（Component Model）。
#
# 与 `scripts/build_plugin.sh`（Rust，核心模块形态）**并列**的两条路：
#   - 核心模块：手写 C 风格 ABI（offset/len + 响应区约定）。
#   - 组件形态：Canonical ABI（类型化 string），跨语言、ABI 稳定。
#
# 流程（照 `wit-bindgen` / `wasm-tools` 的标准链路）：
#   1. moon build --target wasm     → 核心 wasm（含 cabi_realloc 与导出）
#   2. wasm-tools component embed   → 把 WIT 元数据嵌进模块
#   3. wasm-tools component new     → 核心模块 + WIT = 组件
#
# 依赖：`wasm-tools`（https://github.com/bytecodealliance/wasm-tools）。
# 组件形态的**绑定**可用 `wit-bindgen moonbit wit` 生成，但本参考实现
# 手写 Canonical ABI 胶水（`src/cabi`）——MoonBit `wasm` target 的内联
# wasm 白名单不含 GC 内部函数，生成的胶水依赖它们。

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

FIXTURE_DIR="samples/plugin_fixture_component"
OUT_DIR="$ROOT_DIR/samples/plugin_fixture_component/dist"
WASM_OUT="$OUT_DIR/plugin_fixture.component.wasm"

if ! command -v wasm-tools >/dev/null 2>&1; then
  printf '缺少 wasm-tools：https://github.com/bytecodealliance/wasm-tools\n' >&2
  exit 1
fi

cd "$FIXTURE_DIR"

# `moon build` 不产出二进制（只出 WAT）——`moon run` 才会链接出 wasm。
printf '==> Building core wasm (MoonBit, target wasm)\n'
moon run --target wasm --release src/impl/main.mbt

CORE_WASM="src/_build/wasm/release/build/impl/impl.wasm"
if [ ! -f "$CORE_WASM" ]; then
  printf '未找到核心 wasm：%s\n' "$CORE_WASM" >&2
  exit 1
fi

printf '==> Embedding WIT metadata\n'
wasm-tools component embed wit "$CORE_WASM" -o "$CORE_WASM.embedded" --encoding utf16

mkdir -p "$OUT_DIR"

printf '==> Creating component\n'
wasm-tools component new "$CORE_WASM.embedded" -o "$WASM_OUT"

rm -f "$CORE_WASM.embedded"

printf '==> Wrote %s (%s bytes)\n' "$WASM_OUT" "$(wc -c < "$WASM_OUT" | tr -d ' ')"
