///|
/// 插件状态切片：已加载插件、贡献注册、错误。
///
/// 切片纪律（照 `plugins/ai`、`plugins/project` 的状态切片）：**纯数据 +
/// 纯函数迁移**，零 Effect。加载/卸载是服务层的事，回执经 `Msg` 进 update。
///
/// 启停复用既有的 `model.plugin_disabled`（同一个持久化键、同一个开关
/// UI）——插件 id 空间与内置 id（ai/terminal/markdown）并存，互不迁移。

///|
/// 插件贡献注册：插件 id → 它贡献的面。
pub(all) struct PluginRegistry {
  /// 插件 id → 贡献描述
  by_plugin : Map[String, @plugin_contract.PluginContributions]
  /// 插件 id → 面板 id → 面板标题
  panels : Map[String, Map[String, String]]
  /// 插件 id → 命令 id → 命令标题
  commands : Map[String, Map[String, String]]
}

///|
/// 新建空的贡献注册。
pub fn PluginRegistry::new() -> PluginRegistry {
  {
    by_plugin: Map([], capacity=8),
    panels: Map([], capacity=8),
    commands: Map([], capacity=8),
  }
}

///|
/// 插件状态切片。
pub(all) struct PluginState {
  /// 已加载插件的描述（UI 列表用）
  descriptors : Array[@plugin_contract.PluginDescriptor]
  /// 贡献注册
  contributions : PluginRegistry
  /// 插件 id → 失败原因（失败的插件也要在 UI 里说话，不能静默消失）
  errors : Map[String, String]
  /// 本端是否有插件运行时（false = UI 不显示插件入口）
  available : Bool
  /// 插件视图协议 JSON 的缓存：插件 id + 面板 id → JSON
  panel_specs : Map[String, String]
  /// **已发起过视图请求**的面（插件 id + 面板 id）——避免重复请求把
  /// worker 队列打满（同一个面每次重渲都发一次请求会堆积）。
  panel_requested : Map[String, Bool]
  /// 本端**能否安装插件**（浏览器没有文件系统 → 不能）。
  /// UI 据此决定要不要给「安装/卸载」按钮。
  install_available : Bool
  /// 插件根目录（UI 展示用——让用户知道插件装在哪）；空 = 本端没有
  /// 插件目录概念（web 端）。
  plugins_root : String
}

///|
/// 新建空的插件状态。
pub fn PluginState::new() -> PluginState {
  {
    descriptors: [],
    contributions: PluginRegistry::new(),
    errors: Map([], capacity=8),
    available: false,
    panel_specs: Map([], capacity=8),
    panel_requested: Map([], capacity=8),
    install_available: false,
    plugins_root: "",
  }
}

///|
/// 记录本端的安装能力与插件根目录（组合根装配时设置）。
///
/// **为什么进状态切片**：渲染层只有 model，拿不到 `PluginBridge`
/// （那是组合根注入的运行时门面）——故装配时把这两个值抄进切片。
pub fn PluginState::set_install_capability(
  self : PluginState,
  available : Bool,
  plugins_root : String,
) -> PluginState {
  { ..self, install_available: available, plugins_root, }
}

///|
/// 应用加载结果：成功进注册表，失败进错误表。
///
/// **坏插件不阻断好插件**——逐条处理，不因为一条失败就整体丢弃。
pub fn PluginState::apply_load_results(
  self : PluginState,
  results : Array[@plugin_contract.PluginLoadResult],
) -> PluginState {
  let descriptors = self.descriptors
  let registry = self.contributions
  let errors = self.errors
  for result in results {
    match result {
      @plugin_contract.Loaded(manifest~, contributions~) => {
        // descriptor 带**真实 manifest**（名字/版本/职责）——插件管理界面
        // 要显示作者写的信息，不能把 id 当名字。
        let descriptor : @plugin_contract.PluginDescriptor = {
          manifest,
          status: @plugin_contract.Loaded,
        }
        let plugin_id = manifest.id
        // **按 id 替换，不追加**：加载回执是**幂等**的——同一个插件被
        // 重载（web 端轮询、native 端重扫）时不该在列表里堆多份。
        // 追加会让插件的面渲染多份（同一个插件出现 N 次）。
        let kept = descriptors.filter(d => d.manifest.id != plugin_id)
        kept.push(descriptor)
        descriptors.clear()
        for d in kept {
          descriptors.push(d)
        }
        registry.by_plugin.set(plugin_id, contributions)
        let panels : Map[String, String] = Map([], capacity=4)
        for (panel_id, title) in contributions.panels {
          panels.set(panel_id, title)
        }
        let commands : Map[String, String] = Map([], capacity=4)
        for (command_id, title) in contributions.commands {
          commands.set(command_id, title)
        }
        registry.panels.set(plugin_id, panels)
        registry.commands.set(plugin_id, commands)
        errors.remove(plugin_id)
      }
      @plugin_contract.Failed(plugin_id~, reason~) =>
        errors.set(plugin_id, reason)
      @plugin_contract.Skipped(_) => ()
    }
  }
  { ..self, descriptors, contributions: registry, errors, }
}

///|
/// 标记本端是否有插件运行时（组合根装配时设置）。
///
/// 语义：**有运行时** ≠ **有插件**——运行时在但没装任何插件时，
/// 插件页签仍不出现（`plugin_panel_visible` 同时看两者）。
pub fn PluginState::set_available(
  self : PluginState,
  available : Bool,
) -> PluginState {
  { ..self, available, }
}

///|
/// 记录某个插件的视图协议 JSON（渲染时取）。
pub fn PluginState::set_panel_spec(
  self : PluginState,
  plugin_id : String,
  panel_id : String,
  spec : String,
) -> PluginState {
  let panel_specs = self.panel_specs
  panel_specs.set("\{plugin_id}/\{panel_id}", spec)
  { ..self, panel_specs, }
}

///|
/// 取某个插件的视图协议 JSON。
pub fn PluginState::panel_spec(
  self : PluginState,
  plugin_id : String,
  panel_id : String,
) -> String? {
  self.panel_specs.get("\{plugin_id}/\{panel_id}")
}

///|
/// 插件是否启用（复用既有的禁用清单口径）。
pub fn PluginState::is_enabled(
  _self : PluginState,
  plugin_id : String,
  disabled : Array[String],
) -> Bool {
  !disabled.contains(plugin_id)
}

///|
/// 插件贡献的面列表（面板 id + 标题），按插件顺序。
pub fn PluginState::plugin_panels(
  self : PluginState,
  plugin_id : String,
) -> Array[(String, String)] {
  match self.contributions.panels.get(plugin_id) {
    Some(panels) => {
      let out : Array[(String, String)] = []
      for (panel_id, title) in panels {
        out.push((panel_id, title))
      }
      out
    }
    None => []
  }
}

///|
/// 插件贡献的命令列表（命令 id + 标题）。
pub fn PluginState::plugin_commands(
  self : PluginState,
  plugin_id : String,
) -> Array[(String, String)] {
  match self.contributions.commands.get(plugin_id) {
    Some(commands) => {
      let out : Array[(String, String)] = []
      for (command_id, title) in commands {
        out.push((command_id, title))
      }
      out
    }
    None => []
  }
}

///|
/// 加载失败的插件：id + 原因（插件管理界面用——**坏插件必须说话**，
/// 不能静默消失）。
pub fn PluginState::failures(self : PluginState) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for (plugin_id, reason) in self.errors {
    out.push((plugin_id, reason))
  }
  out
}

///|
/// 某个插件的失败原因（没有则 None）。
pub fn PluginState::failure_reason(
  self : PluginState,
  plugin_id : String,
) -> String? {
  self.errors.get(plugin_id)
}

///|
/// 已加载插件的 id 列表（按加载顺序）。
pub fn PluginState::loaded_ids(self : PluginState) -> Array[String] {
  let out : Array[String] = []
  for descriptor in self.descriptors {
    out.push(descriptor.manifest.id)
  }
  out
}

///|
/// 标记某个面板的视图**已被请求过**（避免重复请求）。
pub fn PluginState::mark_panel_requested(
  self : PluginState,
  plugin_id : String,
  panel_id : String,
) -> PluginState {
  let panel_requested = self.panel_requested
  panel_requested.set("\{plugin_id}/\{panel_id}", true)
  { ..self, panel_requested, }
}

///|
/// 某个面板的视图是否已经请求过。
pub fn PluginState::is_panel_requested(
  self : PluginState,
  plugin_id : String,
  panel_id : String,
) -> Bool {
  self.panel_requested.get("\{plugin_id}/\{panel_id}") is Some(_)
}

///|
/// 某个面板的视图是否**已经拿到**（缓存里有）。
pub fn PluginState::has_panel_spec(
  self : PluginState,
  plugin_id : String,
  panel_id : String,
) -> Bool {
  self.panel_specs.get("\{plugin_id}/\{panel_id}") is Some(_)
}

///|
/// 插件加载是否**已完成**（不再需要重试）。
///
/// **判据**：有插件描述 = 加载跑过了（无论成功还是失败——失败也是
/// 「跑完了」）。全空 = 还没跑出结果（web 端：JS 侧插件尚未就绪）。
///
/// 注意 native 端：加载在 worker 上**同步**完成（`PluginsScanned` 回来
/// 时就有描述了），故本判据在 native 端天然为真，不会白跑重试。
pub fn PluginState::is_load_complete(self : PluginState) -> Bool {
  self.descriptors.length() > 0
}
