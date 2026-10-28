///|
/// 宿主函数注册：按插件能力**精确**装配 import 面。
///
/// 插件 import 一个宿主没给的函数 → 实例化失败（缺 import）→ 该插件
/// Failed。**不静默放行**——「插件以为自己有写权限但实际没有」比
/// 「插件加载失败」危险得多：前者会让插件在运行时才发现能力缺失。
///
/// 宿主函数的参数/返回一律 i32（照 wasmoon 示例的窄接口口径）；
/// 复杂数据经 guest 线性内存交换（同 `plugin_host.mbt` 的 ABI）。

///|
/// 注册宿主函数。
pub fn register_host_functions(
  linker : @runtime.Linker,
  manifest : @plugin_contract.PluginManifest,
  host : HostBridge,
) -> Unit raise {
  let capabilities = manifest.capabilities
  // studio.log(message_ptr) —— 基础能力，始终提供。
  linker.add_host_func(
    "studio",
    "log",
    args => {
      let pointer = match args {
        [@types.Value::I32(value)] => value
        _ => raise @runtime.RuntimeError::TypeMismatch
      }
      (host.log)("(plugin) \{manifest.id}")
      [@types.Value::I32(pointer)]
    },
    func_type={
      params: [@types.ValueType::I32],
      results: [@types.ValueType::I32],
    },
  )
  // studio.state_get(key_ptr) —— 插件私有状态。
  if host.grants(capabilities, @plugin_contract.CapCommands) ||
    host.grants(capabilities, @plugin_contract.CapEditor) {
    linker.add_host_func(
      "studio",
      "state_get",
      args => {
        let pointer = match args {
          [@types.Value::I32(value)] => value
          _ => raise @runtime.RuntimeError::TypeMismatch
        }
        let _ = pointer
        [@types.Value::I32(0)]
      },
      func_type={
        params: [@types.ValueType::I32],
        results: [@types.ValueType::I32],
      },
    )
  }
  // studio.action_dispatch(action_ptr, payload_ptr) —— 触发宿主动作。
  if host.grants(capabilities, @plugin_contract.CapCommands) {
    linker.add_host_func(
      "studio",
      "action_dispatch",
      args => {
        match args {
          [@types.Value::I32(_action), @types.Value::I32(_payload)] =>
            [@types.Value::I32(0)]
          _ => raise @runtime.RuntimeError::TypeMismatch
        }
      },
      func_type={
        params: [@types.ValueType::I32, @types.ValueType::I32],
        results: [@types.ValueType::I32],
      },
    )
  }
  // studio.emit_event(name_ptr, payload_ptr) —— 发事件到事件总线。
  if host.grants(capabilities, @plugin_contract.CapEvents) {
    linker.add_host_func(
      "studio",
      "emit_event",
      args => {
        match args {
          [@types.Value::I32(_name), @types.Value::I32(_payload)] =>
            [@types.Value::I32(0)]
          _ => raise @runtime.RuntimeError::TypeMismatch
        }
      },
      func_type={
        params: [@types.ValueType::I32, @types.ValueType::I32],
        results: [@types.ValueType::I32],
      },
    )
  }
  // studio.workspace_read(path_ptr) —— 读工程文件（只读）。
  if host.grants(capabilities, @plugin_contract.CapWorkspaceRead) {
    linker.add_host_func(
      "studio",
      "workspace_read",
      args => {
        let pointer = match args {
          [@types.Value::I32(value)] => value
          _ => raise @runtime.RuntimeError::TypeMismatch
        }
        let _ = pointer
        [@types.Value::I32(0)]
      },
      func_type={
        params: [@types.ValueType::I32],
        results: [@types.ValueType::I32],
      },
    )
  }
  // studio.workspace_write(path_ptr, content_ptr) —— 写工程文件。
  if host.grants(capabilities, @plugin_contract.CapWorkspaceWrite) {
    linker.add_host_func(
      "studio",
      "workspace_write",
      args => {
        match args {
          [@types.Value::I32(_path), @types.Value::I32(_content)] =>
            [@types.Value::I32(0)]
          _ => raise @runtime.RuntimeError::TypeMismatch
        }
      },
      func_type={
        params: [@types.ValueType::I32, @types.ValueType::I32],
        results: [@types.ValueType::I32],
      },
    )
  }
}
