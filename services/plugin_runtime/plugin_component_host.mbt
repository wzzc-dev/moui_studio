///|
/// 插件 ABI·组件形态：入口是 **WebAssembly 组件**（不是核心模块）。
///
/// **与核心模块形态的差别**：
///
/// | | 核心模块（`AbiCore`） | 组件（`AbiComponent`） |
/// | --- | --- | --- |
/// | 字符串传递 | 手写字节搬运（offset/len + 响应区约定） | **Canonical ABI 自动编解码** |
/// | 类型 | 无（自己约定） | **WIT 声明**，编译期检查 |
/// | 导出查找 | `Function::from_export(name)` | `instance.bind("pkg/iface@ver#member")` |
/// | 跨语言 | 需手写 ABI | 官方 `wit-bindgen`（Rust/TS/C/C++/MoonBit） |
///
/// **组件形态的 ABI 定义**（`kernel/plugin_contract/wit/plugin.wit`）：
///
/// ```wit
/// package moui:plugin@0.1.0;
///
/// interface plugin {
///   describe: func() -> string;          // 贡献描述 JSON
///   call: func(request: string) -> string;  // 请求 JSON → 响应 JSON
/// }
///
/// world plugin-world {
///   export plugin;
/// }
/// ```
///
/// **字符串编码**：Canonical ABI 的 `string` 在 **MoonBit 组件**里是
/// **UTF-16LE**（MoonBit 的 `String` 内部即 UTF-16）；wasmoon 按组件声明
/// 的编码解读。实测：按 UTF-8 降级会被 host 当 UTF-16 读 → 乱码。
///
/// **沙箱边界不变**：组件形态**不开放任何 host import**（组件的
/// `world` 只 `export` 不 `import`）——能力白名单仍由核心模块形态的
/// `register_host_functions` 把关；组件形态是**更严格**的一档。

///|
/// 组件形态的 world 名（导出路径前缀）。
///
/// 导出路径格式：`{package}/{interface}@{version}#{member}`。
pub const PLUGIN_COMPONENT_PACKAGE : String = "moui:plugin/plugin@0.1.0"

///|
/// 组件形态的成员名。
pub const PLUGIN_COMPONENT_DESCRIBE : String = "moui:plugin/plugin@0.1.0#describe"

///|
pub const PLUGIN_COMPONENT_CALL : String = "moui:plugin/plugin@0.1.0#call"

///|
/// 已加载的组件形态插件。
pub(all) struct LoadedComponent {
  descriptor : @plugin_contract.PluginDescriptor
  runtime : @component_runtime.ComponentRuntime
  instance : @component_runtime.ComponentInstance
}

///|
/// 组件形态的调用结果 → 字符串。
///
/// 组件返回的应是**类型化字符串**（`ComponentValue::String`）。
/// 其它形态（字节数组等）→ 明确报错，不静默转字节（那会让插件作者
/// 拿到看不懂的错误）。
fn component_string_of(
  values : Array[@component_runtime.ComponentValue],
) -> Result[String, String] {
  match values {
    [value] =>
      match value {
        @component_runtime.String(text) => Ok(text)
        other => Err("组件返回值不是字符串：\{other}")
      }
    _ => Err("组件返回了非预期个数的值")
  }
}

///|
/// 组件形态：取贡献描述（`describe()` → JSON）。
pub fn describe_component(
  instance : @component_runtime.ComponentInstance,
) -> Result[String, String] {
  let function = instance.bind(PLUGIN_COMPONENT_DESCRIBE) catch {
    error =>
      return Err(
        "取组件导出 \{PLUGIN_COMPONENT_DESCRIBE} 失败：\{error}",
      )
  }
  let values = function.call([]) catch {
    error =>
      return Err("调用组件 \{PLUGIN_COMPONENT_DESCRIBE} 失败：\{error}")
  }
  component_string_of(values)
}

///|
/// 组件形态：调用插件（`call(request)` → 响应 JSON）。
pub fn call_component(
  instance : @component_runtime.ComponentInstance,
  request : String,
) -> Result[String, String] {
  let function = instance.bind(PLUGIN_COMPONENT_CALL) catch {
    error =>
      return Err("取组件导出 \{PLUGIN_COMPONENT_CALL} 失败：\{error}")
  }
  let args : Array[@component_runtime.ComponentValue] = [
    @component_runtime.String(request),
  ]
  let values = function.call(args) catch {
    error =>
      return Err("调用组件 \{PLUGIN_COMPONENT_CALL} 失败：\{error}")
  }
  component_string_of(values)
}

///|
/// 组件形态的加载：校验 → 实例化 → 取贡献描述。
///
/// **校验**：组件先过 wasmoon 的组件校验（解析 + 组件类型检查）——
/// 无效组件在分配资源之前就被拒。
pub fn load_component(
  plugin_id : String,
  manifest : @plugin_contract.PluginManifest,
  bytes : Bytes,
) -> Result[(@plugin_contract.PluginContributions, LoadedComponent), String] raise {
  let runtime = @component_runtime.ComponentRuntime::ComponentRuntime()
  let instance = runtime.instantiate(plugin_id, bytes) catch {
    error => return Err("组件实例化失败：\{error}")
  }
  let response = match describe_component(instance) {
    Ok(text) => text
    Err(reason) => return Err(reason)
  }
  let contributions = match @plugin_contract.decode_contributions(response) {
    Ok(value) => value
    Err(errors) => return Err("贡献描述非法：\{debug_inspect(errors)}")
  }
  let descriptor : @plugin_contract.PluginDescriptor = {
    manifest,
    status: @plugin_contract.Loaded,
  }
  Ok((contributions, { descriptor, runtime, instance, }))
}
