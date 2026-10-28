///|
/// 插件 ABI 常量与描述：**契约层的唯一真源**。
///
/// **为什么在这里**：ABI 常量（内存偏移、导出名）是**插件与宿主之间
/// 的契约**——与请求格式、视图协议同属一层，故与它们同处契约层。
///
/// **曾经的债**：native 端（`services/plugin_runtime/plugin_host.mbt`）
/// 与 web 端（`web_wasm/plugin_bridge.js`）各自硬编码了同一批常量。
/// 两处手写副本没有任何机制保证同步——改一处忘另一处，就会出现
/// 「web 能加载、native 报 ABI 不兼容」这类**只在单端暴露**的 bug。
///
/// **现在怎么保证单一真源**：
/// - 常量定义在本文件（`kernel/plugin_contract`）；
/// - native 端直接引用本文件的常量；
/// - web 端的 JS **不硬编码**——由宿主在启动时经 `studio_abi_descriptor`
///   把描述推给 JS（见 `web_wasm/main.mbt`），JS 从 `registerAbi()`
///   读取。
///
/// **描述是 JSON**（不是 MoonBit 常量表）：这样 JS 侧能直接消费，
/// 不必为 JS 单独维护一份投影。

///|
/// 宿主写请求串的落点（guest 内存偏移）。
///
/// 选**低区**（1024）：guest 内存默认只有 1 页（64KB），写在 65536 会
/// 正好越界。插件只读自己收到的指针指向的内容，不碰这块。
pub const PLUGIN_ABI_REQUEST_OFFSET : Int32 = 1024

///|
/// 插件写响应串的落点（guest 内存偏移）。
///
/// 宿主在实例化后调 `studio_set_response_ptr` 告知插件（wasm 内存基址
/// 随实例而定，插件自己算不出来）。
pub const PLUGIN_ABI_RESPONSE_OFFSET : Int32 = 0

///|
/// 插件导出名：统一入口（请求 JSON 进，响应 JSON 出）。
pub const PLUGIN_ABI_CALL_EXPORT : String = "studio_call"

///|
/// 插件导出名：贡献描述（JSON）。
pub const PLUGIN_ABI_DESCRIBE_EXPORT : String = "studio_describe"

///|
/// 插件导出名：设置响应区基址（宿主在实例化后调用一次）。
pub const PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT : String = "studio_set_response_ptr"

///|
/// 插件导出名：上一次导出结果的字节长度。
///
/// MoonBit `wasm` target 的 String 返回值只是指针，宿主推不出长度——
/// 故插件额外导出这个函数报长度（实测：指针前没有可用的长度前缀）。
pub const PLUGIN_ABI_LENGTH_EXPORT : String = "studio_last_result_len"

///|
/// ABI 描述（JSON）：给 JS 侧消费的**唯一**常量来源。
///
/// 字段名用 snake_case（JS 侧直接读，不做转换）。
pub fn plugin_abi_descriptor() -> String {
  let fields : Map[String, Json] = Map([], capacity=8)
  fields["request_offset"] = Json::number(PLUGIN_ABI_REQUEST_OFFSET.to_double())
  fields["response_offset"] = Json::number(
    PLUGIN_ABI_RESPONSE_OFFSET.to_double(),
  )
  fields["call_export"] = Json::string(PLUGIN_ABI_CALL_EXPORT)
  fields["describe_export"] = Json::string(PLUGIN_ABI_DESCRIBE_EXPORT)
  fields["set_response_ptr_export"] = Json::string(
    PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT,
  )
  fields["length_export"] = Json::string(PLUGIN_ABI_LENGTH_EXPORT)
  Json::object(fields).stringify()
}
