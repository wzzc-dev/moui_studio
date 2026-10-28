///|
/// 插件运行时门面：加载 / 调用 / 卸载 / 查询。
///
/// **依赖方向**：本包不 import app（`Msg` 是 app 的类型）——服务层只
/// 产出**协议 JSON**，视图解释在 app 侧（`app/plugin_view_interp.mbt`）。
///
/// **并发**：wasmoon 的 `Store` 绑定创建线程 → 同一插件的调用必须
/// 串行化。本门面按「每个插件一个队列」的形态提供 `call`；调用方
/// （native 组合根的 worker）保证同一插件串行、不同插件并行。
///
/// **失败语义**：单个插件坏 → 只它自己 Failed，其余照常；不 fail-fast。

///|
/// 插件运行时。
pub(all) struct PluginRuntime {
  plugins_root : String
  limits : PluginLimits
  /// 已加载插件：plugin_id → 句柄
  loaded : Map[String, LoadedPlugin]
}

///|
/// 建运行时（此时不加载任何插件——加载是显式动作）。
pub fn PluginRuntime::new(
  plugins_root~ : String,
  limits~ : PluginLimits = PluginLimits::default(),
) -> PluginRuntime {
  { plugins_root, limits, loaded: Map([], capacity=8), }
}

///|
/// 扫描 + 加载全部插件。
///
/// 坏插件不阻断好插件：每个插件独立产出 outcome。
pub fn PluginRuntime::load_all(
  self : PluginRuntime,
  host : HostBridge,
) -> Array[@plugin_contract.PluginLoadResult] raise {
  let outcomes : Array[@plugin_contract.PluginLoadResult] = []
  let scan = scan_plugins(self.plugins_root)
  for candidate in scan.candidates {
    outcomes.push(self.load_candidate(candidate, host))
  }
  // 扫描期就坏掉的清单也要说话——否则用户看不到「为什么插件没出现」。
  for (plugin_id, reason) in scan.invalid {
    outcomes.push(@plugin_contract.Failed(plugin_id~, reason~))
  }
  if scan.truncated {
    outcomes.push(
      @plugin_contract.Skipped(
        reason="插件数量超过扫描上限（\{PLUGIN_SCAN_LIMIT}），部分插件未被扫描",
      ),
    )
  }
  outcomes
}

///|
/// 加载单个插件：读入口 → 按 ABI 形态分派 → 取贡献描述。
///
/// **两种形态**（清单的 `abi` 字段声明，缺省 `core`）：
/// - `AbiCore`：核心 wasm 模块（校验 → 建 Store → 注册宿主函数 →
///   实例化 → 告知响应区基址 → 取贡献描述）。
/// - `AbiComponent`：WebAssembly 组件（组件校验 → 实例化 → 取贡献描述）。
///   组件形态**不注册任何宿主函数**（组件的 world 只 export 不 import）
///   ——它是更严格的一档沙箱。
pub fn PluginRuntime::load_candidate(
  self : PluginRuntime,
  candidate : PluginCandidate,
  host : HostBridge,
) -> @plugin_contract.PluginLoadResult raise {
  let plugin_id = candidate.manifest.id
  let bytes = @x/fs.read_file_to_bytes(candidate.entry_path) catch {
    error =>
      return Failed(
        plugin_id~,
        reason="读取入口文件失败（\{debug_inspect(error)}）",
      )
  }
  match candidate.manifest.abi {
    @plugin_contract.AbiComponent =>
      self.load_component_candidate(plugin_id, candidate.manifest, bytes)
    @plugin_contract.AbiCore =>
      self.load_core_candidate(plugin_id, candidate.manifest, bytes, host)
  }
}

///|
/// 加载核心模块形态的插件。
fn PluginRuntime::load_core_candidate(
  self : PluginRuntime,
  plugin_id : String,
  manifest : @plugin_contract.PluginManifest,
  bytes : Bytes,
  host : HostBridge,
) -> @plugin_contract.PluginLoadResult raise {
  let validated = match validate_plugin_module(bytes) {
    Ok(value) => value
    Err(reason) => return Failed(plugin_id~, reason~)
  }
  let store = match self.limits.make_store() {
    Some(value) => value
    None =>
      return Failed(
        plugin_id~,
        reason="建立插件运行时（配额）失败",
      )
  }
  let linker = @runtime.Linker::with_store(store)
  register_host_functions(linker, manifest, host)
  let module_value = validated.snapshot()
  let instance = @executor.instantiate_with_linker(
    linker, plugin_id, module_value,
  ) catch {
    error => {
      linker.close()
      store.close()
      return Failed(
        plugin_id~,
        reason="实例化失败（宿主函数签名不匹配或模块有未满足的 import）：\{error}",
      )
    }
  }
  // 告知插件响应区基址（wasm 内存基址随实例而定，插件自己算不出来）。
  let memory = match plugin_memory(store, instance) {
    Ok(value) => value
    Err(reason) => {
      linker.close()
      store.close()
      return Failed(plugin_id~, reason~)
    }
  }
  match set_plugin_response_ptr(store, instance, memory) {
    Ok(_) => ()
    Err(reason) => {
      linker.close()
      store.close()
      return Failed(plugin_id~, reason~)
    }
  }
  // 取贡献描述：插件经 describe 导出回一份 JSON。
  let response = describe_plugin_export(store, instance)
  let contributions = match response {
    Ok(text) =>
      match @plugin_contract.decode_contributions(text) {
        Ok(value) => value
        Err(errors) => {
          linker.close()
          store.close()
          return Failed(
            plugin_id~,
            reason="贡献描述非法：\{debug_inspect(errors)}",
          )
        }
      }
    Err(reason) => {
      linker.close()
      store.close()
      return Failed(plugin_id~, reason~)
    }
  }
  let descriptor : @plugin_contract.PluginDescriptor = {
    manifest,
    status: @plugin_contract.Loaded,
  }
  self.loaded.set(plugin_id, CoreModule(descriptor, store, instance))
  @plugin_contract.Loaded(manifest~, contributions~)
}

///|
/// 加载组件形态的插件。
fn PluginRuntime::load_component_candidate(
  self : PluginRuntime,
  plugin_id : String,
  manifest : @plugin_contract.PluginManifest,
  bytes : Bytes,
) -> @plugin_contract.PluginLoadResult raise {
  match load_component(plugin_id, manifest, bytes) {
    Ok((contributions, loaded)) => {
      let manifest_value = loaded.descriptor.manifest
      self.loaded.set(plugin_id, Component(loaded))
      @plugin_contract.Loaded(manifest=manifest_value, contributions~)
    }
    Err(reason) => Failed(plugin_id~, reason~)
  }
}

///|
/// 调用插件：走对应 ABI 形态的统一入口（请求 JSON 进，响应 JSON 出）。
///
/// 插件未加载 → 明确错误（不静默返回空）。
pub fn PluginRuntime::call(
  self : PluginRuntime,
  plugin_id : String,
  request : String,
) -> Result[String, String] {
  match self.loaded.get(plugin_id) {
    Some(CoreModule(_, store, instance)) =>
      call_plugin_export(store, instance, request)
    Some(Component(loaded)) => call_component(loaded.instance, request)
    None => Err("插件未加载：\{plugin_id}")
  }
}

///|
/// 卸载插件：关闭运行时（释放内存/表/GC 域与配额）。
///
/// `Store::close()` 是幂等的；关闭后再次调用该插件 → 明确错误。
pub fn PluginRuntime::unload(self : PluginRuntime, plugin_id : String) -> Unit {
  match self.loaded.get(plugin_id) {
    Some(CoreModule(_, store, _)) => {
      store.close()
      self.loaded.remove(plugin_id)
    }
    Some(Component(loaded)) => {
      loaded.runtime.close()
      self.loaded.remove(plugin_id)
    }
    None => ()
  }
}

///|
/// 卸载全部（Studio 关闭时调用）。
pub fn PluginRuntime::unload_all(self : PluginRuntime) -> Unit {
  let ids : Array[String] = []
  for (plugin_id, _) in self.loaded {
    ids.push(plugin_id)
  }
  for plugin_id in ids {
    self.unload(plugin_id)
  }
}

///|
/// 插件根目录（装卸插件要往这里放/删）。
pub fn PluginRuntime::plugins_root(self : PluginRuntime) -> String {
  self.plugins_root
}

///|
/// 已加载插件的描述（UI 用）。
pub fn PluginRuntime::descriptors(
  self : PluginRuntime,
) -> Array[@plugin_contract.PluginDescriptor] {
  let out : Array[@plugin_contract.PluginDescriptor] = []
  for (_, plugin) in self.loaded {
    out.push(
      match plugin {
        CoreModule(descriptor, _, _) => descriptor
        Component(loaded) => loaded.descriptor
      },
    )
  }
  out
}

///|
/// 插件是否已加载。
pub fn PluginRuntime::is_loaded(
  self : PluginRuntime,
  plugin_id : String,
) -> Bool {
  self.loaded.contains(plugin_id)
}
