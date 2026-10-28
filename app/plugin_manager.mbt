///|
/// 插件管理面板：**独立模态对话框**（不是设置面板里的一组）。
///
/// **为什么独立**：成熟 IDE 的插件管理都是独立面板（VS Code 的扩展页、
/// JetBrains 的插件设置）——它要装/卸/看详情/看状态，设置面板塞不下，
/// 也不该塞（设置是「配置」，插件管理是「操作」）。
///
/// **成熟度的三条口径**：
/// 1. **状态要说全**：已装 + 已禁用 + 加载失败，各有自己的呈现。
/// 2. **禁用 ≠ 卸载**：禁用只过滤入口（文件留着，可逆）；卸载删目录
///    （不可逆，须确认）。UI 上分开呈现，文案也分开。
/// 3. **操作要有回执**：装完/卸完都要说话（含失败原因）——点了没反应
///    会让用户以为没生效。
///
/// **本端能力缺席即显式声明**：浏览器没有文件系统 → 不显示「安装/
/// 卸载」按钮，并说明原因（不给必然失败的按钮）。

///|
/// 插件管理对话框。
pub fn plugin_manager_dialog(
  model : Model,
  t : @i18n.Translator,
  can_install : Bool,
  plugins_root : String,
) -> @moui.View[Msg] {
  let rows : Array[@moui.View[Msg]] = []
  // 标题行：标题 + 关闭按钮
  rows.push(
    @views.row(
      [
        @views.text(
          text(t, "app.plugin.manager.title"),
          theme=@chrome.studio_theme(),
          role=Subtitle,
          width=300.0,
          height=26.0,
          align=TextStart,
        ).foreground(@chrome.ide_text()),
        @views.spacer(min_length=0.0, weight=1.0),
        @views.button(
          text(t, "app.plugin.manager.close"),
          on_click=PluginManagerClose,
          variant=@style.Ghost,
          width=64.0,
          height=26.0,
        ),
      ],
      spacing=8.0,
      align=Center,
    ).frame(width=420.0),
  )
  rows.push(@views.divider(color=@chrome.ide_border()))
  // 安装入口：本端不支持就不给按钮（只说明原因）。
  rows.push(plugin_manager_install_row(model, t, can_install))
  // 插件根目录（让用户知道插件装在哪）——web 端没有这个概念，不显示。
  if plugins_root != "" {
    rows.push(
      @views.text(
        text(t, "app.plugin.manager.root") + " " + plugins_root,
        theme=@chrome.studio_theme(),
        width=420.0,
        height=14.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    )
  }
  rows.push(@views.divider(color=@chrome.ide_border()))
  // 插件列表：已装（含禁用态）+ 加载失败
  let list = plugin_manager_list(model, t, can_install)
  if list.is_empty() {
    rows.push(
      @views.text(
        text(t, "app.plugin.manager.empty"),
        theme=@chrome.studio_theme(),
        width=420.0,
        height=16.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    )
  } else {
    for item in list {
      rows.push(item)
    }
  }
  // 操作回执（成功/失败都要说话）
  if model.plugin_manager.notice != "" {
    let color = if model.plugin_manager.notice_is_error {
      @chrome.ide_warning()
    } else {
      @chrome.ide_success()
    }
    rows.push(
      @views.text(
        model.plugin_manager.notice,
        theme=@chrome.studio_theme(),
        width=420.0,
        height=16.0,
        align=TextStart,
      ).foreground(color),
    )
  }
  @views.container(
    @views.column(rows, spacing=6.0),
    background=@chrome.ide_panel(),
    corner_radius=6.0,
    width=452.0,
    padding=16.0,
  )
}

///|
/// 安装入口行：「安装插件」按钮 + 本端不可用时的说明。
fn plugin_manager_install_row(
  model : Model,
  t : @i18n.Translator,
  can_install : Bool,
) -> @moui.View[Msg] {
  if !can_install {
    // 本端不能装 → **不给按钮**，只说明为什么（不给必然失败的按钮）。
    return @views.text(
      text(t, "app.plugin.manager.install_unavailable"),
      theme=@chrome.studio_theme(),
      width=420.0,
      height=16.0,
      align=TextStart,
    ).foreground(@chrome.ide_text_faint())
  }
  let busy = model.plugin_manager.is_busy()
  @views.row(
    [
      @views.button(
        text(t, "app.plugin.manager.install"),
        // 忙碌时禁用（避免重复提交）——空操作，不是静默失败。
        on_click=if busy { Msg::Noop } else { PluginInstallRequested("") },
        variant=if busy { @style.Outline } else { @style.Primary },
        width=104.0,
        height=28.0,
      ),
      @views.text(
        text(t, "app.plugin.manager.install_hint"),
        theme=@chrome.studio_theme(),
        width=300.0,
        height=28.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    ],
    spacing=8.0,
    align=Center,
  ).frame(width=420.0)
}

///|
/// 插件列表：已装插件（含禁用态）+ 加载失败的插件。
///
/// **失败也要在列表里**（坏插件必须说话）——但**没有卸载按钮**
/// （它没装上，卸什么？）。
fn plugin_manager_list(
  model : Model,
  t : @i18n.Translator,
  can_install : Bool,
) -> Array[@moui.View[Msg]] {
  let out : Array[@moui.View[Msg]] = []
  for descriptor in model.plugin_state.descriptors {
    let plugin_id = descriptor.manifest.id
    let active = plugin_active(model, plugin_id)
    let busy = model.plugin_manager.is_busy_with(plugin_id)
    let name = descriptor.manifest.name
    let version = descriptor.manifest.version
    let subtitle = if descriptor.manifest.description == "" {
      version
    } else {
      version + " · " + descriptor.manifest.description
    }
    // 三个动作：启用/禁用、卸载、选中看详情。
    //
    // **禁用不需要确认**（可逆：文件留着）；**卸载需要**（删目录）。
    let buttons : Array[@moui.View[Msg]] = []
    buttons.push(
      @views.button(
        text(t, if active { "app.plugin.disable" } else { "app.plugin.enable" }),
        on_click=TogglePlugin(plugin_id),
        variant=if active { @style.Outline } else { @style.Primary },
        width=64.0,
        height=26.0,
      ),
    )
    if can_install {
      buttons.push(
        @views.button(
          text(t, "app.plugin.manager.uninstall"),
          // 忙碌时禁用（避免重复提交）。
          on_click=if busy {
            Msg::Noop
          } else {
            PluginUninstallRequested(plugin_id)
          },
          variant=@style.Ghost,
          width=64.0,
          height=26.0,
        ),
      )
    }
    let row_children : Array[@moui.View[Msg]] = []
    row_children.push(
      @views.column(
        [
          // 插件名是**按钮**——点了展开详情（能力/面板/命令/ABI）。
          // 选中态用主色标出，用户知道当前在看谁。
          @views.button(
            name,
            on_click=PluginManagerSelect(plugin_id),
            variant=if model.plugin_manager.selected == plugin_id {
              @style.Primary
            } else {
              @style.Ghost
            },
            width=240.0,
            height=18.0,
          ),
          @views.text(
            subtitle,
            theme=@chrome.studio_theme(),
            width=240.0,
            height=14.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_faint()),
        ],
        spacing=1.0,
      ),
    )
    row_children.push(@views.spacer(min_length=6.0, weight=1.0))
    for button in buttons {
      row_children.push(button)
    }
    out.push(
      @views.row(row_children, spacing=8.0, align=Center).frame(
        width=420.0,
        height=36.0,
      ),
    )
    // 详情：选中时展开（版本/能力/面板/命令）。
    if model.plugin_manager.selected == plugin_id {
      out.push(plugin_manager_detail(model, t, plugin_id))
    }
  }
  // 加载失败的插件：列出来 + 原因（无卸载按钮——它没装上）。
  for (plugin_id, reason) in model.plugin_state.failures() {
    out.push(
      @views.column(
        [
          @views.text(
            plugin_id,
            theme=@chrome.studio_theme(),
            width=240.0,
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_text()),
          @views.text(
            text(t, "app.plugin.wasm.failed") + " " + reason,
            theme=@chrome.studio_theme(),
            width=410.0,
            height=14.0,
            align=TextStart,
          ).foreground(@chrome.ide_warning()),
        ],
        spacing=1.0,
      ).frame(width=420.0),
    )
  }
  out
}

///|
/// 插件详情：能力、贡献的面与命令。
///
/// 展开在选中插件下方（不弹第二个对话框——避免模态套模态）。
fn plugin_manager_detail(
  model : Model,
  t : @i18n.Translator,
  plugin_id : String,
) -> @moui.View[Msg] {
  let rows : Array[@moui.View[Msg]] = []
  // 找选中插件的描述（遍历而非 find——Array 无 find 方法）。
  let mut descriptor : @plugin_contract.PluginDescriptor? = None
  for item in model.plugin_state.descriptors {
    if item.manifest.id == plugin_id {
      descriptor = Some(item)
    }
  }
  let manifest = match descriptor {
    Some(value) => value.manifest
    None => return @views.empty()
  }
  rows.push(
    @views.text(
      text(t, "app.plugin.manager.detail") + " " + manifest.id,
      theme=@chrome.studio_theme(),
      width=410.0,
      height=14.0,
      align=TextStart,
    ).foreground(@chrome.ide_accent()),
  )
  // 能力
  let caps : Array[String] = []
  for capability in manifest.capabilities {
    caps.push(capability.token())
  }
  let cap_text = if caps.is_empty() {
    text(t, "app.plugin.manager.no_capabilities")
  } else {
    caps.join("、")
  }
  rows.push(
    @views.text(
      text(t, "app.plugin.manager.capabilities") + " " + cap_text,
      theme=@chrome.studio_theme(),
      width=410.0,
      height=14.0,
      align=TextStart,
    ).foreground(@chrome.ide_text_muted()),
  )
  // 贡献的面
  let panels = model.plugin_state.plugin_panels(plugin_id)
  if !panels.is_empty() {
    let names : Array[String] = []
    for (_, title) in panels {
      names.push(title)
    }
    rows.push(
      @views.text(
        text(t, "app.plugin.manager.panels") + " " + names.join("、"),
        theme=@chrome.studio_theme(),
        width=410.0,
        height=14.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_muted()),
    )
  }
  // 贡献的命令
  let commands = model.plugin_state.plugin_commands(plugin_id)
  if !commands.is_empty() {
    let names : Array[String] = []
    for (_, title) in commands {
      names.push(title)
    }
    rows.push(
      @views.text(
        text(t, "app.plugin.manager.commands") + " " + names.join("、"),
        theme=@chrome.studio_theme(),
        width=410.0,
        height=14.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_muted()),
    )
  }
  // ABI 形态（core / component）——用户需要知道插件是哪种形态。
  rows.push(
    @views.text(
      text(t, "app.plugin.manager.abi") + " " + manifest.abi.token(),
      theme=@chrome.studio_theme(),
      width=410.0,
      height=14.0,
      align=TextStart,
    ).foreground(@chrome.ide_text_muted()),
  )
  @views.column(rows, spacing=2.0).frame(width=420.0)
}
