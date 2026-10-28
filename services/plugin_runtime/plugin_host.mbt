///|
/// wasmoon 集成：每个插件一个独立 `Store`（独立内存/表/GC 域），
/// 实例化后调导出拿贡献描述。
///
/// **ABI 口径**（实测确定，见 `PLUGIN_ABI_*` 的说明）：
/// - 宿主函数用 `Linker::add_host_func(module, name, fn, func_type)` 注册，
///   参数/返回值走 `i32`。
/// - 导出调用用 `Function::from_export` + `.call([RootedValue::i32(n)])`。
/// - **字符串经 guest 线性内存交换**：按 MoonBit `wasm` target 的标准
///   字符串 ABI（i32 指针 → UTF-16LE 字节 + 前置 4 字节小端长度）。
///
/// 边界（诚实声明）：
/// - wasmoon 自述为 experimental + insecure，**不是安全边界**。本层的
///   隔离 = 独立 Store + 能力白名单 + 资源配额 + 不开放 WASI。
/// - guest trap 变成 `Err`，不让 Studio 崩；但 wasmoon 的 trap 处理
///   未经审计，文档必须写明「插件仅应来自可信来源」。
/// - `Store` 与其 continuation 绑定创建线程 → **同一插件的调用必须
///   串行化**。

///|
/// 插件 ABI：宿主与插件约定的**字符串传递方式**（标准 C 风格）。
///
/// **约定**：
/// - 字符串 = **UTF-8 字节**（不是 UTF-16）。
/// - 导出签名：`fn(ptr : i32, len : i32) -> i32`。
///   - 入参：请求字节在 guest 线性内存的 `ptr` 处，长度 `len` 字节。
///   - 返回：响应字节的长度（i32）；响应字节在**同一个** guest 内存的
///     `PLUGIN_ABI_RESPONSE_OFFSET` 处。
/// - 插件另导出 `studio_last_result_len() -> i32` 报出**自己**返回的
///   字符串长度（宿主据此读回，见下）。
///
/// **为什么用 C 风格而不是 MoonBit 的 String**：MoonBit `wasm` target 的
/// `String` 是 **GC 引用**（`[p-8: kind][p-4: length][p: data]`），
/// 宿主无法构造——写进去的裸内存不会被插件识别为 String（实测插件读到
/// 长度为 0）。而 C 风格的 `(ptr, len)` 是跨语言 ABI 的通用形态，宿主
/// 与插件都按字节处理，不涉及任何 GC 语义。
///
/// **因此插件不应用 MoonBit 编写**（MoonBit 无法导出这种 ABI）；
/// 用 Rust / C / TinyGo 等输出 `wasm32-unknown-unknown` 的工具链即可。
/// 参考实现见 `samples/plugin_fixture/`（Rust 版）。
/// **ABI 常量在契约层**（`kernel/plugin_contract/plugin_abi.mbt`）——
/// 本文件不再自带副本：native 与 web 必须共用同一份定义，否则改一处
/// 忘另一处就会出现「只在单端暴露」的 ABI 不兼容。
pub const PLUGIN_ABI_RESPONSE_OFFSET : Int32 = @plugin_contract.PLUGIN_ABI_RESPONSE_OFFSET

///|
/// 宿主写请求串的落点（guest 内存偏移）。
pub const PLUGIN_ABI_REQUEST_OFFSET : Int32 = @plugin_contract.PLUGIN_ABI_REQUEST_OFFSET

///|
/// 插件导出名：统一入口（请求 JSON 进，响应 JSON 出）。
pub const PLUGIN_ABI_CALL_EXPORT : String = @plugin_contract.PLUGIN_ABI_CALL_EXPORT

///|
/// 插件导出名：贡献描述（JSON）。
pub const PLUGIN_ABI_DESCRIBE_EXPORT : String = @plugin_contract.PLUGIN_ABI_DESCRIBE_EXPORT

///|
/// 插件导出名：设置响应区基址（宿主在实例化后调用一次）。
pub const PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT : String = @plugin_contract.PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT

///|
/// 插件导出名：上一次导出结果的字节长度。
pub const PLUGIN_ABI_LENGTH_EXPORT : String = @plugin_contract.PLUGIN_ABI_LENGTH_EXPORT

///|
/// 已加载插件的运行时句柄。持有它 = 持有该插件的运行时。
///
/// **两种 ABI 形态并存**（清单的 `abi` 字段声明）：
/// - `CoreModule`：核心 wasm 模块 + 独立 `Store`（手写 C 风格 ABI）。
/// - `Component`：WebAssembly 组件 + 独立 `ComponentRuntime`
///   （Canonical ABI，类型化字符串）。
///
/// 两者都是「一个插件一份运行时」——隔离与配额语义一致。
pub(all) enum LoadedPlugin {
  CoreModule(
    @plugin_contract.PluginDescriptor,
    @runtime.Store,
    @runtime.ModuleInstance
  )
  Component(LoadedComponent)
}

///|
/// 资源配额：每个插件一份，防止单个插件吃光宿主内存。
pub(all) struct PluginLimits {
  memory_bytes : Int64
  table_elements : Int64
  gc_bytes : Int64
  gc_objects : Int64
  code_bytes : Int64
  pending_work : Int64
  input_bytes : Int64
  compilation_units : Int64
  /// 单次导出的执行时限（毫秒）
  call_timeout_ms : Int32
}

///|
/// 默认配额。数值取「够跑正常插件，但不至于拖垮宿主」的量级——
/// 真实插件（编译期工具）需要更大，可由组合根按 profile 覆盖。
pub fn PluginLimits::default() -> PluginLimits {
  {
    memory_bytes: 256L * 1024L * 1024L,
    table_elements: 100000L,
    gc_bytes: 64L * 1024L * 1024L,
    gc_objects: 200000L,
    code_bytes: 32L * 1024L * 1024L,
    pending_work: 10000L,
    input_bytes: 16L * 1024L * 1024L,
    compilation_units: 1048576L,
    call_timeout_ms: 5000,
  }
}

///|
/// 按配额建 Store。配额建不出来（非法数值）→ 返回 None（不 fail-fast，
/// 由调用方记成该插件的失败原因）。
pub fn PluginLimits::make_store(self : PluginLimits) -> @runtime.Store? {
  let budget = @runtime.ResourceBudget::new(
    memory_bytes=self.memory_bytes,
    table_elements=self.table_elements,
    gc_bytes=self.gc_bytes,
    gc_objects=self.gc_objects,
    code_bytes=self.code_bytes,
    pending_work=self.pending_work,
    input_bytes=self.input_bytes,
    compilation_units=self.compilation_units,
  ) catch {
    _ => return None
  }
  let store = @runtime.Store::Store(resource_budget=Some(budget)) catch {
    _ => return None
  }
  Some(store)
}

///|
/// 解析并校验 wasm 字节 → 受保护的模块证据。
///
/// 校验先于实例化（wasmoon 的纪律：无效模型在分配 Store 之前就被拒）。
pub fn validate_plugin_module(
  bytes : Bytes,
) -> Result[@validator.ValidatedModule, String] {
  let parsed = @parser.parse_module(bytes) catch {
    error => return Err("wasm 解析失败：\{error}")
  }
  let validated = @validator.ValidatedModule::new(parsed) catch {
    error => return Err("wasm 校验失败：\{error}")
  }
  Ok(validated)
}

///|
/// 取插件的线性内存。插件必须导出且只有一块线性内存——ABI 的前提。
pub fn plugin_memory(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Result[@runtime.Memory, String] {
  if instance.mem_addrs.length() == 0 {
    return Err(
      "插件没有线性内存（ABI 要求插件导出一块线性内存）",
    )
  }
  let memory = store.get_mem(instance.mem_addrs[0]) catch {
    error => return Err("取插件内存失败：\{error}")
  }
  Ok(memory)
}

///|
/// 往 guest 内存写一段字节。越界 → Err（不崩宿主）。
pub fn write_guest_bytes(
  memory : @runtime.Memory,
  offset : Int32,
  bytes : Bytes,
) -> Result[Unit, String] {
  let limit = memory.byte_len()
  if offset < 0 || offset.to_int64() + bytes.length().to_int64() > limit {
    return Err(
      "写 guest 内存越界（offset=\{offset}，长度=\{bytes.length()}，内存=\{limit}）",
    )
  }
  for i in 0..<bytes.length() {
    memory.write_byte(offset + (i : Int32), bytes[i])
  }
  Ok(())
}

///|
/// 读 guest 内存的一段字节。越界 → Err。
pub fn read_guest_bytes(
  memory : @runtime.Memory,
  offset : Int32,
  length : Int32,
) -> Result[Bytes, String] {
  let limit = memory.byte_len()
  if offset < 0 || length < 0 {
    return Err("读 guest 内存参数非法")
  }
  if offset.to_int64() + length.to_int64() > limit {
    return Err(
      "读 guest 内存越界（offset=\{offset}，长度=\{length}，内存=\{limit}）",
    )
  }
  Ok(memory.read_bytes(offset, length))
}

///|
/// 把一个字符串按 **UTF-8 字节** 写进 guest 内存，返回内容指针。
///
/// C 风格 ABI：指针指向内容，长度由调用方单独传（插件按 `(ptr, len)`
/// 读）。不写任何 GC 头——插件只看字节。
pub fn write_guest_string(
  memory : @runtime.Memory,
  offset : Int32,
  text : String,
) -> Result[Int32, String] {
  let bytes = @utf8.encode(text)
  match write_guest_bytes(memory, offset, bytes) {
    Ok(_) => Ok(offset)
    Err(reason) => Err(reason)
  }
}

///|
/// 从 guest 内存读回一段 **UTF-8 字节** 并解成字符串。
pub fn read_guest_string(
  memory : @runtime.Memory,
  pointer : Int32,
  byte_length : Int32,
) -> Result[String, String] {
  if pointer < 0 || byte_length < 0 {
    return Err(
      "guest 字符串参数非法（pointer=\{pointer}，长度=\{byte_length}）",
    )
  }
  if byte_length == 0 {
    return Ok("")
  }
  let raw = match read_guest_bytes(memory, pointer, byte_length) {
    Ok(bytes) => bytes
    Err(reason) => return Err(reason)
  }
  // 解码非法 UTF-8 → 明确错误（不静默替换成替换字符——那会让插件的
  // 错误内容变成看似合法的文本）。
  let decoded = @utf8.decode(raw) catch {
    _ => return Err("guest 字符串不是合法 UTF-8")
  }
  Ok(decoded)
}

///|
/// 告知插件响应区在 guest 内存里的基址（实例化后调一次）。
///
/// wasm 的线性内存基址随实例而定，插件自己算不出来——必须由宿主告知。
/// 插件没有这个导出 → 不兼容（明确报错，不静默跳过）。
pub fn set_plugin_response_ptr(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  _memory : @runtime.Memory,
) -> Result[Unit, String] {
  let function = @executor.Function::from_export(
    store,
    instance,
    PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT,
  ) catch {
    error =>
      return Err(
        "取导出 \{PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT} 失败（插件 ABI 不兼容）：\{error}",
      )
  }
  // 响应区在内存里的绝对地址 = 内存基址 + 偏移。内存基址由 wasmoon 的
  // Memory 句柄给出（`Memory::base` 不存在 → 用偏移 0 表达「内存起点」）。
  // 插件只需要「相对自己内存起点的偏移」，故传偏移即可。
  ignore(
    function.call([@runtime.RootedValue::i32(PLUGIN_ABI_RESPONSE_OFFSET)]) catch {
      error => {
        function.close()
        return Err(
          "调用 \{PLUGIN_ABI_SET_RESPONSE_PTR_EXPORT} 失败：\{error}",
        )
      }
    },
  )
  function.close()
  Ok(())
}

///|
/// 调用插件导出（标准 C ABI）：写请求 JSON → 调 `studio_call(ptr, len)`
/// → 读响应 JSON。
///
/// 插件导出签名：`fn(ptr : i32, len : i32) -> i32`，指针指向 UTF-8 字节。
pub fn call_plugin_export(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
  request : String,
) -> Result[String, String] {
  let memory = match plugin_memory(store, instance) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let request_pointer = match
    write_guest_string(memory, PLUGIN_ABI_REQUEST_OFFSET, request) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let request_length = @utf8.encode(request).length()
  let function = @executor.Function::from_export(
    store,
    instance,
    PLUGIN_ABI_CALL_EXPORT,
  ) catch {
    error => return Err("取导出 \{PLUGIN_ABI_CALL_EXPORT} 失败：\{error}")
  }
  let results = function.call([
    @runtime.RootedValue::i32(request_pointer),
    @runtime.RootedValue::i32((request_length : Int32)),
  ]) catch {
    error => {
      function.close()
      return Err("调用 \{PLUGIN_ABI_CALL_EXPORT} 失败：\{error}")
    }
  }
  // 返回值是响应字节数；同时用 `studio_last_result_len` 交叉核对
  // （插件可能返回 0 而把长度放在 last_result_len 里）。
  let returned_length = match results {
    [value] => {
      let scalar = value.scalar() catch {
        error => {
          function.close()
          return Err("读取导出返回值失败：\{error}")
        }
      }
      match scalar {
        @types.Value::I32(length) => length
        other => {
          function.close()
          return Err("导出返回值不是 i32 长度：\{other}")
        }
      }
    }
    _ => {
      function.close()
      return Err("导出返回了非预期个数的值")
    }
  }
  function.close()
  let response_length = match read_plugin_result_length(store, instance) {
    Some(length) =>
      if length > returned_length {
        length
      } else {
        returned_length
      }
    None => returned_length
  }
  read_guest_string(memory, PLUGIN_ABI_RESPONSE_OFFSET, response_length)
}

///|
/// 取插件上一次导出的字节长度（`studio_last_result_len`）。
pub fn read_plugin_result_length(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Int32? {
  let function = @executor.Function::from_export(
    store,
    instance,
    PLUGIN_ABI_LENGTH_EXPORT,
  ) catch {
    _ => return None
  }
  let results = function.call([]) catch {
    _ => {
      function.close()
      return None
    }
  }
  let length = match results {
    [value] => {
      let scalar = value.scalar() catch {
        _ => {
          function.close()
          return None
        }
      }
      match scalar {
        @types.Value::I32(length) => length
        _ => {
          function.close()
          return None
        }
      }
    }
    _ => {
      function.close()
      return None
    }
  }
  function.close()
  Some(length)
}

///|
/// 取插件的贡献描述 JSON（调 `studio_describe` 导出）。
pub fn describe_plugin_export(
  store : @runtime.Store,
  instance : @runtime.ModuleInstance,
) -> Result[String, String] {
  let memory = match plugin_memory(store, instance) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let function = @executor.Function::from_export(
    store,
    instance,
    PLUGIN_ABI_DESCRIBE_EXPORT,
  ) catch {
    error =>
      return Err("取导出 \{PLUGIN_ABI_DESCRIBE_EXPORT} 失败：\{error}")
  }
  let results = function.call([]) catch {
    error => {
      function.close()
      return Err("调用 \{PLUGIN_ABI_DESCRIBE_EXPORT} 失败：\{error}")
    }
  }
  let returned_length = match results {
    [value] => {
      let scalar = value.scalar() catch {
        error => {
          function.close()
          return Err("读取导出返回值失败：\{error}")
        }
      }
      match scalar {
        @types.Value::I32(length) => length
        other => {
          function.close()
          return Err("导出返回值不是 i32 长度：\{other}")
        }
      }
    }
    _ => {
      function.close()
      return Err("导出返回了非预期个数的值")
    }
  }
  function.close()
  let response_length = match read_plugin_result_length(store, instance) {
    Some(length) =>
      if length > returned_length {
        length
      } else {
        returned_length
      }
    None => returned_length
  }
  read_guest_string(memory, PLUGIN_ABI_RESPONSE_OFFSET, response_length)
}
