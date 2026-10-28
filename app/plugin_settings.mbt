///|
/// WASM 插件的管理界面（设置面板里的「WASM 插件」分组）。
///
/// **为什么单独一组**：内置插件（ai/terminal/markdown）是**静态装配**的，
/// 启停只是过滤贡献项入口；WASM 插件是**运行时加载**的，有自己的
/// 生命周期与失败态。两者的启停语义相同（同一个 `plugin_disabled`），
/// 但要说的话不一样——所以分组呈现，不混在一张表里。
///
/// **坏插件必须说话**：加载失败的插件也要列出来并给出原因。静默消失
/// 会让用户以为「插件没装」。

///|
/// WASM 插件分组：已加载插件（可启停）+ 加载失败的插件（只报原因）。
///
/// 本端没有插件运行时（web 入口 / 教学版 profile）→ **整组不出现**
/// （能力缺席就不留空页，与既有纪律一致）。
pub fn wasm_plugin_section(
  model : Model,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  if !model.plugin_state.available {
    return @views.empty()
  }
  let rows : Array[@moui.View[Msg]] = []
  // 已加载插件：名字（来自清单）+ 版本 + 启停按钮。
  for descriptor in model.plugin_state.descriptors {
    rows.push(wasm_plugin_row(model, t, descriptor))
  }
  // 加载失败的插件：id + 原因（无启停按钮——它没加载上）。
  for (plugin_id, reason) in model.plugin_state.failures() {
    rows.push(wasm_plugin_failure_row(t, plugin_id, reason))
  }
  if rows.is_empty() {
    return @views.text(
      text(t, "app.plugin.wasm.empty"),
      theme=@chrome.studio_theme(),
      width=392.0,
      height=16.0,
    ).foreground(@chrome.ide_text_faint())
  }
  @views.column(rows, spacing=4.0)
}

///|
/// 一个已加载的 WASM 插件行：名字 + 版本/职责 + 启停按钮。
fn wasm_plugin_row(
  model : Model,
  t : @i18n.Translator,
  descriptor : @plugin_contract.PluginDescriptor,
) -> @moui.View[Msg] {
  let manifest = descriptor.manifest
  let active = plugin_active(model, manifest.id)
  let subtitle = if manifest.description == "" {
    manifest.version
  } else {
    manifest.version + " · " + manifest.description
  }
  @views.row(
    [
      @views.column(
        [
          @views.text(
            manifest.name,
            theme=@chrome.studio_theme(),
            width=220.0,
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_text()),
          @views.text(
            subtitle,
            theme=@chrome.studio_theme(),
            width=220.0,
            height=14.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_faint()),
        ],
        spacing=1.0,
      ),
      @views.spacer(min_length=6.0, weight=1.0),
      @views.button(
        text(t, if active { "app.plugin.disable" } else { "app.plugin.enable" }),
        on_click=TogglePlugin(manifest.id),
        variant=if active { Outline } else { Primary },
        width=76.0,
        height=26.0,
      ),
    ],
    spacing=8.0,
    align=Center,
  ).frame(width=392.0, height=36.0)
}

///|
/// 一个加载失败的插件行：id + 失败原因（**没有启停按钮**——它没加载上，
/// 给一个开关是假的）。
fn wasm_plugin_failure_row(
  t : @i18n.Translator,
  plugin_id : String,
  reason : String,
) -> @moui.View[Msg] {
  @views.column(
    [
      @views.text(
        plugin_id,
        theme=@chrome.studio_theme(),
        width=220.0,
        height=16.0,
        align=TextStart,
      ).foreground(@chrome.ide_text()),
      @views.text(
        text(t, "app.plugin.wasm.failed") + " " + reason,
        theme=@chrome.studio_theme(),
        width=220.0,
        height=14.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    ],
    spacing=1.0,
  ).frame(width=392.0, height=36.0)
}
