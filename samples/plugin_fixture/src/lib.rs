//! 最小 WASM 插件（MoUI Studio 插件系统参考实现 / E2E 用）。
//!
//! **为什么用 Rust 而不是 MoonBit**：MoonBit `wasm` target 的 `String` 是
//! **GC 引用**（`[p-8: kind][p-4: length][p: data]`），宿主无法构造——
//! 写进 guest 内存的裸字节不会被插件识别为 String（实测插件读到长度
//! 0）。跨语言 ABI 必须用**标准 C 风格**：字符串 = UTF-8 字节 + 显式
//! 长度，宿主与插件都只当字节处理，不涉及任何 GC 语义。
//!
//! **ABI**（与 `services/plugin_runtime/plugin_host.mbt` 的 `PLUGIN_ABI_*`
//! 一致）：
//!
//! - `studio_describe() -> *const u8`（长度由 `studio_last_result_len`
//!   给出）：返回贡献描述 JSON。
//! - `studio_call(ptr: *const u8, len: usize) -> usize`：请求 JSON 在
//!   `ptr` 处（`len` 字节），返回响应字节数；响应写在响应区。
//! - `studio_last_result_len() -> usize`：上一次返回的字节数。
//!
//! 响应区偏移由宿主约定（`PLUGIN_ABI_RESPONSE_OFFSET` = 0）；本实现通过
//! `#[no_mangle] extern "C"` 导出的 `studio_response_ptr()` 告知宿主。

use std::cell::RefCell;

/// 响应区偏移（宿主约定：0）。
const RESPONSE_OFFSET: usize = 0;

/// 动作请求的 `format` 字段值（与 `kernel/plugin_contract` 的
/// `PLUGIN_ACTION_FORMAT` 一致）——只有这种请求才改插件状态。
const ACTION_FORMAT: &str = "moui.studio.plugin.action";

/// 插件状态（进程内保持；wasm 实例在宿主 Store 里，状态随实例存活）。
thread_local! {
    static STATE: RefCell<State> = RefCell::new(State {
        clicks: 0,
        last_action: String::new(),
    });
}

struct State {
    clicks: i32,
    last_action: String,
}

/// 上一次返回的字节数（宿主据此读回）。
static mut LAST_RESULT_LEN: usize = 0;

/// 响应区在**自己**线性内存里的偏移（相对内存起点）。
///
/// 语义是**相对偏移**而非绝对地址：宿主的内存句柄 API（wasmoon 的
/// `Memory::write_byte(offset, ..)`、浏览器的 `Uint8Array(memory.buffer)`
/// 下标）都用相对偏移，插件必须与之一致。
static mut RESPONSE_OFFSET_PTR: usize = 0;

#[no_mangle]
pub extern "C" fn studio_last_result_len() -> usize {
    unsafe { LAST_RESULT_LEN }
}

/// 响应区偏移（显式导出以免两端各写一份常量）。
#[no_mangle]
pub extern "C" fn studio_response_ptr() -> usize {
    unsafe { RESPONSE_OFFSET_PTR }
}

/// 设置响应区偏移（宿主在实例化后调用一次）。
#[no_mangle]
pub extern "C" fn studio_set_response_ptr(offset: usize) {
    unsafe {
        RESPONSE_OFFSET_PTR = offset;
    }
}

/// 贡献描述：声明一个面板与一条命令。
///
/// 返回**响应字节数**（响应内容写在响应区）——与 `studio_call` 同一形态，
/// 宿主读回时用 `studio_last_result_len` 取长度。
#[no_mangle]
pub extern "C" fn studio_describe() -> usize {
    let json = r#"{"format":"moui.studio.plugin.contrib","format_version":1,"panels":{"main":"Fixture 面板"},"commands":{"reset":"重置计数"}}"#;
    store_response(json.as_bytes())
}

/// 统一入口：处理请求 JSON，返回响应 JSON。
///
/// 两种请求（靠 `format` 区分）：
/// - 视图请求（`moui.studio.plugin.viewreq`）→ 回该面板的视图。
/// - 动作请求（`moui.studio.plugin.action`）→ 处理后回**新**视图。
///
/// **只有动作请求才改状态**：视图请求**不动**计数与「最后动作」。
/// 否则宿主每次渲染都问一次视图（web 端渲染期实时问插件），刚记下的
/// 「最后动作」会被随后的视图请求抹掉——界面回到 `last=` 空。
#[no_mangle]
pub extern "C" fn studio_call(ptr: *const u8, len: usize) -> usize {
    let request = if ptr.is_null() || len == 0 {
        String::new()
    } else {
        let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
        String::from_utf8_lossy(bytes).to_string()
    };
    // 按 `format` 区分请求种类：动作请求才改状态。
    if extract_json_string(&request, "format") == ACTION_FORMAT {
        let action = extract_json_string(&request, "action_id");
        STATE.with(|s| {
            let mut state = s.borrow_mut();
            state.last_action = action.clone();
            if action == "increment" {
                state.clicks += 1;
            } else if action == "reset" {
                state.clicks = 0;
            }
        });
    }
    let view = panel_view();
    store_response(view.as_bytes())
}

/// 视图：一个文本（显示计数与最后动作）+ 一个按钮。
fn panel_view() -> String {
    let (clicks, last) = STATE.with(|s| {
        let state = s.borrow();
        (state.clicks, state.last_action.clone())
    });
    let text = format!("点击次数：{} | last={}", clicks, last);
    format!(
        r#"{{"format":"moui.studio.plugin.view","format_version":1,"key":"fixture-root","node":"Column","children":[{{"key":"fixture-count","node":"Text","text":{}}},{{"key":"fixture-button","node":"Button","label":"点我","action":"increment"}}]}}"#,
        json_string(&text)
    )
}

/// 把响应写进响应区，返回其长度。
fn store_response(bytes: &[u8]) -> usize {
    unsafe {
        // 相对偏移：直接加到自己的线性内存起点（wasm 线性内存的地址 0
        // 就是 guest 内存起点 —— 插件自己写自己，地址就是偏移）。
        let ptr = RESPONSE_OFFSET_PTR + RESPONSE_OFFSET;
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), ptr as *mut u8, bytes.len());
        LAST_RESULT_LEN = bytes.len();
    }
    bytes.len()
}

/// 从 JSON 里取一个字符串字段（够用的最小实现——参考实现不必引依赖）。
fn extract_json_string(json: &str, key: &str) -> String {
    let needle = format!("\"{}\":\"", key);
    let Some(start) = json.find(&needle) else {
        return String::new();
    };
    let rest = &json[start + needle.len()..];
    let Some(end) = rest.find('"') else {
        return String::new();
    };
    rest[..end].to_string()
}

/// 把字符串转成 JSON 字符串字面量（含转义）。
fn json_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for ch in text.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}
