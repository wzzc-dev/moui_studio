///|
/// 插件面板：插件贡献的面在底栏页签内渲染。
///
/// 纪律（与「能力缺席就不留空页」同款，见 `ide_root.mbt` 的说明）：
/// - 本端没有插件运行时 → **不注册页签**（页签行不出现空位）。
/// - 没有已加载插件 → 不注册页签。
/// - 插件面板的正文由**插件的视图协议 JSON** 渲染（app 侧解释器）。
/// - 插件贡献的命令在面板内成区展示——**不进全局命令面板**
///   （既有 `command_registry_wbtest` 硬编码 43/40 条断言，插件命令
///   并入会打破那条回归；且插件命令的语义属于插件自己的面）。

///|
/// 插件面板是否应当出现（本端有运行时 + 至少一个启用且加载成功的插件）。
///
/// **单一路径**：插件描述一律来自 model 的 `descriptors`——web 端与
/// native 端同款（web 端插件经 `PluginsScanned` 回执进 model）。
pub fn plugin_panel_visible(model : Model) -> Bool {
  if !model.plugin_state.available {
    return false
  }
  for descriptor in model.plugin_state.descriptors {
    if descriptor.status is @plugin_contract.Loaded &&
      plugin_active(model, descriptor.manifest.id) {
      return true
    }
  }
  false
}

///|
/// 插件面板要渲染的插件 id 列表（**每个插件只出现一次**）。
///
/// **单一路径**：插件描述一律来自 model 的 `descriptors`（`PluginsScanned`
/// 回执）——web 端与 native 端同款。故 web 插件**不会**重复出现
/// （曾经的重复源于 web 端额外那条「渲染期实时问插件」的绕行路径，
/// 已删除）。
///
/// 纯函数（不构造视图）→ 可直接断言。
pub fn plugin_panel_plugin_ids(model : Model) -> Array[String] {
  let ids : Array[String] = []
  for descriptor in model.plugin_state.descriptors {
    let plugin_id = descriptor.manifest.id
    if !(descriptor.status is @plugin_contract.Loaded) {
      continue
    }
    if !plugin_active(model, plugin_id) {
      continue
    }
    if model.plugin_state.plugin_panels(plugin_id).is_empty() {
      continue
    }
    ids.push(plugin_id)
  }
  ids
}

///|
/// 插件面板正文：逐个插件渲染其贡献的面。
///
/// **单一渲染路径**：插件的视图**一律**来自 model 缓存的
/// `panel_spec`（`PluginPanelSpec` 消息回填）。web 端与 native 端
/// 同款。
///
/// **为什么曾经有第二条路径**：web 端插件就绪晚于宿主构造 runtime，
/// 宿主「拉」插件列表必然拉到空，于是早期加了一条「渲染期实时问
/// 插件」的绕行路径（进程级槽位 + 同步调用）。那条路径有三个问题：
///
/// 1. **重复渲染**——web 插件的贡献也进 model 的 `descriptors`，
///    两条路径都渲染 → 同一个插件的面出现两份（且内容不同：实时路径
///    带最新动作，缓存路径是首次快照）；
/// 2. **每帧调插件**——渲染期同步调用插件，插件是**不受信任的代码**，
///    不该在渲染路径上跑；
/// 3. **状态竞争**——实时路径的视图请求会覆盖动作刚记下的状态。
///
/// 通道修好后（`studio_plugins_changed` → 重绘 → 重试节拍 →
/// `PluginsScanned` → `PluginPanelSpec`），这条路径不再必要，故删除。
pub fn plugin_panel_body(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  _height : Double,
) -> @moui.View[Msg] {
  let sections : Array[@moui.View[Msg]] = []
  // web 端：插件描述**也在** model 的 `descriptors` 里（`PluginsScanned`
  // 回执）——与 native 端同一条路径，故此处不再单独遍历槽位。
  //
  // 但 web 端的清单只有 id（浏览器没有文件系统，拿不到 `plugin.json`），
  // 故标题用**插件 id**（native 端用清单里的名字）。
  let web_contributions = web_plugin_contributions()
  for descriptor in model.plugin_state.descriptors {
    let plugin_id = descriptor.manifest.id
    if !(descriptor.status is @plugin_contract.Loaded) {
      continue
    }
    if !plugin_active(model, plugin_id) {
      continue
    }
    let panels = model.plugin_state.plugin_panels(plugin_id)
    if panels.is_empty() {
      continue
    }
    // 标题：web 端用 id，native 端用清单里的名字。
    let title = if web_contributions.get(plugin_id) is Some(_) {
      plugin_id
    } else {
      descriptor.manifest.name
    }
    sections.push(
      @views.column(
        [
          @views.text(
            text(t, "app.plugin.panel.title"),
            theme=@chrome.studio_theme(),
            width~,
            height=16.0,
          ).foreground(@chrome.ide_text()),
          @views.text(title, theme=@chrome.studio_theme(), width~, height=14.0).foreground(
            @chrome.ide_text_faint(),
          ),
        ],
        spacing=1.0,
      ),
    )
    for (panel_id, panel_title) in panels {
      sections.push(
        @views.container(
          @views.column(
            [
              @views.text(
                panel_title,
                theme=@chrome.studio_theme(),
                width~,
                height=15.0,
              ).foreground(@chrome.ide_text()),
              plugin_panel_view(model, plugin_id, panel_id, width),
            ],
            spacing=2.0,
          ),
          background=@chrome.ide_panel(),
          width~,
          padding=6.0,
        ),
      )
    }
  }
  if sections.is_empty() {
    // 面板已注册但内容为空（插件加载后又被禁用）：显示一句实话。
    return @views.text(
      text(t, "app.plugin.panel.empty"),
      theme=@chrome.studio_theme(),
      width~,
      height=16.0,
    ).foreground(@chrome.ide_text_faint())
  }
  @views.column(sections, spacing=6.0)
}

///|
/// 单个插件面板的视图：取缓存的协议 JSON → 解释为宿主视图。
///
/// 没有缓存（插件还没回视图）→ 显示占位文案，不崩。
fn plugin_panel_view(
  model : Model,
  plugin_id : String,
  panel_id : String,
  width : Double,
) -> @moui.View[Msg] {
  match model.plugin_state.panel_spec(plugin_id, panel_id) {
    Some(spec) =>
      match
        interpret_plugin_view_json(spec, {
          plugin_id,
          panel_id,
          button_key: fn(action_id) {
            plugin_id + "/" + panel_id + "/" + action_id
          },
          on_action: fn(action_id, payload) {
            PluginAction(plugin_id, panel_id, action_id, payload)
          },
        }) {
        Some(view) => view
        None =>
          @views.text(
            text(translator(model), "app.plugin.panel.invalid"),
            theme=@chrome.studio_theme(),
            width~,
            height=16.0,
          ).foreground(@chrome.ide_text_faint())
      }
    None =>
      @views.text(
        text(translator(model), "app.plugin.panel.pending"),
        theme=@chrome.studio_theme(),
        width~,
        height=16.0,
      ).foreground(@chrome.ide_text_faint())
  }
}
