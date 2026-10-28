///|
/// v4 IDE 壳的对话框层：设置、AI 历史、toast、命令面。
/// 全部走同一个 overlay_host（顶层唯一宿主）——presentation 宿主只包一层，
/// 每个功能的显隐由各自的 presented 标志控制，关闭时不产生命中层。

// ============================================================================
// 设置对话框
// ============================================================================

///|
/// 设置：语言 / 双轨 / 编译可达性 / provider（端点·模型·密钥·假模型切换）
/// / 草稿自动保存说明 / 关于段。密钥只进会话内存——这里显式说明。
pub fn settings_dialog(model : Model, t : @i18n.Translator) -> @moui.View[Msg] {
  let rows : Array[@moui.View[Msg]] = [
    @views.text(
      text(t, "app.settings.title"),
      theme=@chrome.studio_theme(),
      role=Subtitle,
      width=392.0,
      height=26.0,
      align=TextStart,
    ).foreground(@chrome.ide_text()),
    @views.divider(color=@chrome.ide_border()),
    group_label(t, "app.settings.group.workspace"),
    @views.row(
      [
        @views.button(
          text(t, "app.perspective.visual"),
          on_click=SetPerspective(PsVisual),
          variant=if model.perspective is PsVisual { Primary } else { Outline },
          width=124.0,
          height=28.0,
        ),
        @views.button(
          text(t, "app.perspective.code"),
          on_click=SetPerspective(PsCode),
          variant=if model.perspective is PsCode { Primary } else { Outline },
          width=124.0,
          height=28.0,
        ),
        @views.button(
          text(t, "app.perspective.ai"),
          on_click=SetPerspective(PsAi),
          variant=if model.perspective is PsAi { Primary } else { Outline },
          width=124.0,
          height=28.0,
        ),
      ],
      spacing=8.0,
    ),
    group_label(t, "app.settings.group.language"),
    @views.row(
      [
        @views.button(
          text(t, "app.lang.zh"),
          on_click=if model.language is ZhHans {
            Msg::Noop
          } else {
            SwitchLanguage
          },
          variant=if model.language is ZhHans { Primary } else { Outline },
          width=100.0,
          height=28.0,
        ),
        @views.button(
          text(t, "app.lang.en"),
          on_click=if model.language is En { Msg::Noop } else { SwitchLanguage },
          variant=if model.language is En { Primary } else { Outline },
          width=100.0,
          height=28.0,
        ),
      ],
      spacing=8.0,
    ),
    group_label(t, "app.settings.group.track"),
    @views.row(
      [
        @views.button(
          text(t, "app.track.interpret"),
          on_click=SetRunTrack(Interpret),
          variant=if current_track(model) is Interpret {
            Primary
          } else {
            Outline
          },
          width=124.0,
          height=28.0,
        ),
        @views.button(
          text(t, "app.track.compile"),
          on_click=SetRunTrack(Compile),
          variant=if current_track(model) is Compile {
            Primary
          } else {
            Outline
          },
          width=124.0,
          height=28.0,
        ),
      ],
      spacing=8.0,
    ),
    // 编译轨可达性说明：英文版 687/893pt，同样折行。
    @chrome.hint_lines_view(
      if model.compile_track_available {
        text(t, "app.settings.compile.available")
      } else {
        text(t, "app.settings.compile.unavailable")
      },
      392.0,
      @chrome.ide_text_faint(),
      3,
    ),
    group_label(t, "app.settings.group.appearance"),
    @views.row(
      [
        @views.button(
          text(t, "app.settings.dark"),
          on_click=if model.ui_dark { Msg::Noop } else { ToggleUiDark },
          variant=if model.ui_dark { Primary } else { Outline },
          width=124.0,
          height=28.0,
        ),
        @views.button(
          text(t, "app.settings.light"),
          on_click=if model.ui_dark { ToggleUiDark } else { Msg::Noop },
          variant=if model.ui_dark { Outline } else { Primary },
          width=124.0,
          height=28.0,
        ),
      ],
      spacing=8.0,
    ),
    group_label(t, "app.settings.group.shortcuts"),
    shortcut_row(t, "app.shortcut.save", "Ctrl+S"),
    shortcut_row(t, "app.shortcut.open", "Ctrl+O"),
    shortcut_row(t, "app.shortcut.export", "Ctrl+E"),
    shortcut_row(t, "app.shortcut.run", "Ctrl+Enter"),
    shortcut_row(t, "app.shortcut.undo", "Ctrl+Z"),
    shortcut_row(t, "app.shortcut.redo", "Ctrl+Shift+Z"),
    shortcut_row(t, "app.shortcut.palette", "Ctrl+K"),
    shortcut_row(t, "app.shortcut.complete", "Ctrl+Space"),
    shortcut_row(t, "app.shortcut.duplicate", "Ctrl+D"),
    shortcut_row(t, "app.shortcut.copy", "Ctrl+C"),
    shortcut_row(t, "app.shortcut.paste", "Ctrl+V"),
    shortcut_row(t, "app.shortcut.front", "Ctrl+]"),
    shortcut_row(t, "app.shortcut.back", "Ctrl+["),
    shortcut_row(t, "app.shortcut.multi", "Ctrl+M"),
    shortcut_row(t, "app.shortcut.nudge", "方向键 / Arrow keys"),
    group_label(t, "app.settings.group.plugins"),
    // G7.3 插件管理:静态装配的诚实形态——列出已装配插件,启用/禁用
    // 只过滤贡献项入口;「安装新插件需重新构建」如实声明。
    plugin_row(model, t, "ai"),
    plugin_row(model, t, "terminal"),
    plugin_row(model, t, "markdown"),
    @views.text(
      text(t, "app.plugin.static_note"),
      theme=@chrome.studio_theme(),
      width=392.0,
      height=16.0,
      align=TextStart,
    ).foreground(@chrome.ide_text_faint()),
    // WASM 插件（M8）：**运行时加载**的一组，与上面的静态装配插件分开
    // 呈现——启停语义相同（同一个 plugin_disabled），但要说的话不同
    // （有版本/职责，且加载失败要报原因）。本端没有插件运行时时整组
    // 不出现（能力缺席就不留空页）。
    group_label(t, "app.settings.group.wasm_plugins"),
    wasm_plugin_section(model, t),
    // 插件管理面板入口：**独立模态对话框**（装/卸/详情都在里面）。
    // 设置面板只给入口——管理是「操作」，不该挤在「配置」里。
    //
    // 本端没有插件运行时时整组不出现（能力缺席就不留空页）。
    plugin_manager_entry(model, t),
    group_label(t, "app.settings.group.provider"),
    field_label(t, "app.ai.endpoint", 392.0),
    @views.text_field(
      model.ai_ui.provider_endpoint,
      on_input=value => AiUiOp(@ai.SetProviderEndpoint(value)),
      width=392.0,
      height=@chrome.FIELD_HEIGHT,
    ),
    field_label(t, "app.ai.model", 392.0),
    @views.text_field(
      model.ai_ui.provider_model,
      on_input=value => AiUiOp(@ai.SetProviderModel(value)),
      width=392.0,
      height=@chrome.FIELD_HEIGHT,
    ),
    field_label(t, "app.ai.key", 392.0),
    @views.row(
      [
        @views.text_field(
          if model.ai_ui.provider_key_revealed {
            model.ai_ui.provider_key
          } else {
            mask_key(model.ai_ui.provider_key)
          },
          on_input=value => AiUiOp(@ai.SetProviderKey(value)),
          width=320.0,
          height=@chrome.FIELD_HEIGHT,
        ),
        @chrome.action_chip(
          text(t, "app.ai.reveal"),
          AiUiOp(@ai.ToggleProviderKeyReveal),
          @chrome.Quiet,
          @chrome.FIELD_HEIGHT,
        ),
      ],
      spacing=8.0,
    ),
    // 提示按可用宽折行——英文版这句话 766pt，392pt 的单行必然溢出。
    @chrome.hint_lines_view(
      text(t, "app.ai.key_hint"),
      392.0,
      @chrome.ide_warning(),
      3,
    ),
    @views.divider(color=@chrome.ide_border()),
    @chrome.hint_lines_view(
      text(t, "app.settings.draft_hint"),
      392.0,
      @chrome.ide_text_faint(),
      2,
    ),
    @chrome.fill_row(
      [
        @views.spacer(min_length=4.0, weight=1.0),
        @chrome.action_chip(
          text(t, "app.settings.close"),
          AiUiOp(@ai.ToggleSettings),
          @chrome.Primary,
          28.0,
        ),
      ],
      392.0,
      8.0,
      Center,
    ),
  ]
  @views.container(
    @views.scroll_view(
      @views.column(rows, spacing=6.0),
      width=400.0,
      height=520.0,
      shows_indicator=true,
    ),
    width=432.0,
    background=@chrome.ide_elevated(),
    corner_radius=8.0,
    border=Some(
      @graphics.BorderStyle::new(
        brush=@graphics.Brush::solid(@chrome.ide_border()),
        width=1.0,
      ),
    ),
    padding=16.0,
  )
}

///|
/// 密钥掩码：固定 12 个点（长度不泄露）。
fn mask_key(key : String) -> String {
  if key == "" {
    ""
  } else {
    "••••••••••••"
  }
}

///|
/// 插件管理面板入口（设置面板里的按钮）。
///
/// 本端没有插件运行时 → **整行不出现**（能力缺席就不留空页）。
fn plugin_manager_entry(model : Model, t : @i18n.Translator) -> @moui.View[Msg] {
  if !model.plugin_state.available {
    return @views.empty()
  }
  @views.row(
    [
      @views.button(
        text(t, "app.plugin.manager.title"),
        on_click=PluginManagerOpen,
        variant=@style.Outline,
        width=124.0,
        height=28.0,
      ),
      @views.text(
        text(t, "app.plugin.manager.open_hint"),
        theme=@chrome.studio_theme(),
        width=252.0,
        height=28.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    ],
    spacing=8.0,
    align=Center,
  )
}

///|
/// 分组小标题。
fn group_label(t : @i18n.Translator, key : String) -> @moui.View[Msg] {
  @views.text(
    text(t, key),
    theme=@chrome.studio_theme(),
    width=392.0,
    height=20.0,
    align=TextStart,
  ).foreground(@chrome.ide_accent())
}

// ============================================================================
// AI 历史
// ============================================================================

///|
/// AI 历史：会话内提案回放（采纳/拒绝 + 摘要 + diff 行）。
pub fn ai_history_dialog(
  model : Model,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let rows : Array[@moui.View[Msg]] = [
    @views.text(
      text(t, "app.ai.history"),
      theme=@chrome.studio_theme(),
      role=Subtitle,
      width=520.0,
      height=26.0,
      align=TextStart,
    ).foreground(@chrome.ide_text()),
    @views.divider(color=@chrome.ide_border()),
  ]
  if model.ai_sessions.current().proposal_history.length() == 0 {
    rows.push(
      @views.text(
        text(t, "app.ai.history.empty"),
        theme=@chrome.studio_theme(),
        width=520.0,
        height=24.0,
        align=TextStart,
      ).foreground(@chrome.ide_text_faint()),
    )
  } else {
    // 新的在上（回放先看最近一次）
    let mut index = model.ai_sessions.current().proposal_history.length() - 1
    while index >= 0 {
      let record = model.ai_sessions.current().proposal_history[index]
      rows.push(
        @views.container(
          @views.column(
            [
              @views.row(
                [
                  @chrome.count_badge(
                    "\{record.seq}",
                    if record.accepted {
                      1
                    } else {
                      3
                    },
                  ),
                  @views.text(
                    if record.accepted {
                      text(t, "app.ai.hist_accepted")
                    } else {
                      text(t, "app.ai.hist_rejected")
                    },
                    theme=@chrome.studio_theme(),
                    width=72.0,
                    height=18.0,
                    align=TextStart,
                  ).foreground(
                    if record.accepted {
                      @chrome.ide_success()
                    } else {
                      @chrome.ide_danger()
                    },
                  ),
                  @views.text(
                    record.summary,
                    theme=@chrome.studio_theme(),
                    width=380.0,
                    height=18.0,
                    align=TextStart,
                  ).foreground(@chrome.ide_text()),
                ],
                spacing=6.0,
                align=Center,
              ),
              @views.column(diff_line_views(record.diff, 520.0), spacing=0.0),
            ],
            spacing=4.0,
          ),
          background=@chrome.ide_panel(),
          corner_radius=4.0,
          width=552.0,
          padding=8.0,
        ),
      )
      index = index - 1
    }
  }
  rows.push(
    @views.row(
      [
        @views.spacer(min_length=4.0, weight=1.0),
        @chrome.action_chip(
          text(t, "app.settings.close"),
          AiUiOp(@ai.ToggleAiHistory),
          @chrome.Primary,
          28.0,
        ),
      ],
      spacing=8.0,
    ),
  )
  @views.container(
    @views.column(rows, spacing=6.0),
    width=520.0,
    background=@chrome.ide_elevated(),
    corner_radius=8.0,
    border=Some(
      @graphics.BorderStyle::new(
        brush=@graphics.Brush::solid(@chrome.ide_border()),
        width=1.0,
      ),
    ),
    padding=12.0,
  )
}

///|
/// diff 行渲染：+ 绿 / − 红 / 上下文灰（最多 8 行——历史是回放不是全量）。
fn diff_line_views(
  diff : Array[@proposals.DiffEntry],
  width : Double,
) -> Array[@moui.View[Msg]] {
  let views : Array[@moui.View[Msg]] = []
  let mut shown = 0
  for entry in diff {
    if shown >= 8 {
      break
    }
    let (marker, label) = match entry.op {
      @proposals.Added => ("+", entry.new_text)
      @proposals.Removed => ("-", entry.old_text)
      @proposals.Changed => ("-", entry.old_text)
    }
    views.push(@chrome.diff_row(marker, label, width))
    shown = shown + 1
  }
  views
}

// ============================================================================
// toast
// ============================================================================

///|
/// toast 层：底部居中的堆叠条（最新在上）。warning 用暖色左边条。
pub fn toast_host(base : @moui.View[Msg], model : Model) -> @moui.View[Msg] {
  let specs : Array[@views.PresentationSpec[Msg]] = []
  let toasts = recent_toasts(model.toasts)
  let mut index = 0
  for toast in toasts {
    let label = toast.text
    let warning = toast.warning
    specs.push(
      @views.PresentationSpec::new(
        id="studio-toast-\{index}",
        kind=@views.PresentationKind::Toast,
        content=toast_view(label, warning),
        placement=Some(
          @views.PresentationPlacement::new(
            candidates=[@views.PresentationPlacementCandidate::BelowCenter],
            viewport_insets=@core.Insets::all(16.0 + index.to_double() * 36.0),
          ),
        ),
        dismiss=@views.PresentationDismissPolicy::new(
          outside_tap=true,
          message=Some(DismissToast(index)),
        ),
        presented=true,
      ),
    )
    index = index + 1
  }
  @views.overlay_host(base, specs)
}

///|
/// 最近的 toast（最多 TOAST_LIMIT 条，新的在前——视觉上最新在最上）。
fn recent_toasts(toasts : Array[ToastEntry]) -> Array[ToastEntry] {
  let out : Array[ToastEntry] = []
  let mut index = toasts.length() - 1
  while index >= 0 && out.length() < TOAST_LIMIT {
    out.push(toasts[index])
    index = index - 1
  }
  out
}

///|
/// 单条 toast：左色条 + 文案。
fn toast_view(label : String, warning : Bool) -> @moui.View[Msg] {
  @views.container(
    @views.row(
      [
        @views.container(
          @views.text("", width=3.0, height=1.0),
          background=if warning {
            @chrome.ide_warning()
          } else {
            @chrome.ide_success()
          },
          width=3.0,
          padding=0.0,
        ),
        @views.padding_xy(
          @views.text(
            label,
            theme=@chrome.studio_theme(),
            width=300.0,
            height=20.0,
            align=TextStart,
          ).foreground(@chrome.ide_text()),
          horizontal=10.0,
          vertical=0.0,
        ),
      ],
      spacing=0.0,
      align=Center,
    ),
    background=@chrome.ide_elevated(),
    corner_radius=4.0,
    border=Some(
      @graphics.BorderStyle::new(
        brush=@graphics.Brush::solid(@chrome.ide_border()),
        width=1.0,
      ),
    ),
    height=32.0,
    padding=0.0,
  )
}

// ============================================================================
// 状态栏
// ============================================================================

///|
/// 状态栏：工作区 / 文件 + 脏标 / 位置 / 编码+语言 / 警告·错误计数 /
/// 构建读数 / 运行态。
pub fn ide_status_bar(
  model : Model,
  t : @i18n.Translator,
  width : Double,
) -> @moui.View[Msg] {
  let workspace = match model.workspace {
    WsVisual => text(t, "app.ws.visual")
    WsCode => text(t, "app.ws.code")
    WsPreview => text(t, "app.ws.preview")
    WsEmpty => text(t, "app.ws.empty")
  }
  let file = match current_handler(model) {
    None => text(t, "app.statusbar.nofile")
    Some(handler) => "\{handler.control_name}.\{handler.event.tag()}"
  }
  let pending = pending_side_effects(model)
  let errors = audit_error_count(model)
  let cells : Array[(String, Int32)] = [
    ("MoUI Studio", 4),
    (workspace, 0),
    (
      file + (if model.dirty { " ●" } else { "" }),
      if model.dirty {
        2
      } else {
        0
      },
    ),
    (status_position(model), 0),
    ("UTF-8 · MoonBit", 0),
    ("warn \{pending}", if pending > 0 { 2 } else { 0 }),
    ("err \{errors}", if errors > 0 { 3 } else { 0 }),
  ]
  let build = status_build_label(model)
  let cells_final = if build == "" {
    cells
  } else {
    let extended = cells
    extended.push(
      (text(t, build), if build == "app.statusbar.build_ok" { 1 } else { 3 }),
    )
    extended
  }
  let run_cell = if app_running(model) {
    (text(t, "app.statusbar.running"), 1)
  } else {
    (text(t, "app.statusbar.idle"), 0)
  }
  let all = cells_final
  all.push(run_cell)
  // 悬停提示优先占位：图标悬停时状态栏左端显示该图标的说明，离开即还原。
  // 放在最前而不是最后：状态栏尾格在窄窗被裁，提示不能被裁掉。
  let cells_with_hint = if model.hover_hint == "" {
    all
  } else {
    let hinted : Array[(String, Int32)] = [(model.hover_hint, 0)]
    for cell in all {
      hinted.push(cell)
    }
    hinted
  }
  // VS Code 状态栏口径：**左组**（应用/工作区/文件标识）+ **右组**
  // （行号/编码/警告错误/运行状态），中间 weight spacer 撑开。
  let split = cells_with_hint.length().clamp(min=3, max=99).min(4)
  let left_cells : Array[(String, Int32)] = []
  let right_cells : Array[(String, Int32)] = []
  let mut cursor = 0
  for cell in cells_with_hint {
    if cursor < split {
      left_cells.push(cell)
    } else {
      right_cells.push(cell)
    }
    cursor = cursor + 1
  }
  let left_width = (width * 0.45).max(300.0)
  let right_width = (width - left_width).max(200.0)
  @views.container(
    @views.row(
      [
        @chrome.status_cells(left_cells, left_width, false),
        @views.spacer(min_length=8.0, weight=1.0),
        @chrome.status_cells(right_cells, right_width, true),
      ],
      spacing=0.0,
      align=Center,
    ).frame(width~),
    background=@chrome.ide_panel_alt(),
    height=@chrome.STATUSBAR_HEIGHT,
    padding=0.0,
  )
}

// ============================================================================
// 命令面（Studio 自有命令贡献表）
// ============================================================================

///|
/// Studio 命令贡献表（M5）：命令面板（`studio_commands` 派生描述符）与
/// 执行通道（`run_studio_command`）共用同一份定义，表与处理器不可能再漂移。
/// `label_key == ""` 的命令不进面板——只保留内部/兼容入口。
fn studio_command_registry() -> Array[@wb.CommandContribution[StudioCtx, Msg]] {
  let ws = "app.command.group.workspace"
  let pane = "app.command.group.pane"
  let ai = "app.command.group.ai"
  let run_group = "app.command.group.run"
  let file = "app.command.group.file"
  let view = "app.command.group.mode"
  let tmpl = "app.templates"
  [
    cmd(
      "studio.mode.visual",
      "app.command.perspective.visual",
      ws,
      SetPerspective(PsVisual),
    ),
    cmd(
      "studio.mode.code",
      "app.command.perspective.code",
      ws,
      SetPerspective(PsCode),
    ),
    cmd(
      "studio.mode.ai",
      "app.command.perspective.ai",
      ws,
      SetPerspective(PsAi),
    ),
    cmd("studio.workspace.visual", "", ws, SetPerspective(PsVisual)),
    cmd("studio.workspace.code", "", ws, SetPerspective(PsCode)),
    cmd(
      "studio.workspace.preview",
      "app.command.ws.preview",
      ws,
      SetWorkSpace(WsPreview),
    ),
    cmd(
      "studio.workspace.design",
      "app.command.ws.design",
      ws,
      SetPerspective(PsDesign),
    ),
    cmd(
      "studio.workspace.blocks",
      "app.command.ws.blocks",
      ws,
      SetPerspective(PsBlocks),
    ),
    cmd_with("studio.left.toggle", "app.topbar.left_panel", pane, ctx => {
      SetLeftView(
        if ctx.model.left_view is LeftHidden {
          LeftTree
        } else {
          LeftHidden
        },
      )
    }),
    cmd(
      "studio.pane.live",
      "app.command.pane.live",
      pane,
      WorkbenchOp(@wb.TogglePaneLive),
    ),
    cmd(
      "studio.pane.blocks",
      "app.command.pane.blocks",
      pane,
      WorkbenchOp(@wb.TogglePaneBlocks),
    ),
    cmd(
      "studio.pane.split",
      "app.command.pane.split",
      pane,
      WorkbenchOp(@wb.SetSplitRatio(0.55)),
    ),
    cmd(
      "studio.left.tree",
      "app.command.left.tree",
      pane,
      SetLeftView(LeftTree),
    ),
    cmd(
      "studio.left.data",
      "app.command.left.data",
      pane,
      SetLeftView(LeftData),
    ),
    cmd_with("studio.right.toggle", "app.command.right.toggle", pane, ctx => {
      SetRightView(
        if ctx.model.right_view is RvHidden {
          // AI 模式展开 = 工作区面板（更改/文件——VS Code 智能体模式口径）;
          // 其余模式 = 检查器页
          if ctx.model.perspective is PsAi {
            RvWorkspace
          } else {
            RvContext
          }
        } else {
          RvHidden
        },
      )
    }),
    cmd("studio.right.context", "", pane, SetRightView(RvContext)),
    cmd("studio.right.ai", "app.command.right.ai", pane, SetRightView(RvAi)),
    cmd(
      "studio.ctx.runtime",
      "app.command.ctx.runtime",
      pane,
      SetContextTab(CtxRuntime),
    ),
    cmd(
      "studio.code.complete",
      "app.command.code.complete",
      pane,
      TriggerCompletion,
    ),
    cmd("studio.code.jump", "app.command.code.jump", pane, JumpToDeclaration),
    cmd("studio.bottom.toggle", "app.command.bottom.toggle", pane, ToggleBottom),
    cmd(
      "studio.bottom.audit",
      "app.command.bottom.audit",
      pane,
      SetBottomTab(BtAudit),
    ),
    cmd(
      "studio.bottom.console",
      "app.command.bottom.console",
      pane,
      SetBottomTab(BtConsole),
    ),
    cmd(
      "studio.bottom.problems",
      "app.command.bottom.problems",
      pane,
      SetBottomTab(BtProblems),
    ),
    cmd(
      "studio.audit.settle_all",
      "app.command.audit.settle_all",
      pane,
      AuditSettleAll("app.audit.confirmed"),
    ),
    cmd_with("studio.ai.new_session", "app.command.ai.new_session", ai, ctx => {
      AiSessionOp(AiSessionCreate(civil_seconds(ctx.model.clock)))
    }),
    cmd(
      "studio.ai.search",
      "app.command.ai.search_sessions",
      ai,
      AiUiOp(@ai.ToggleSessionSearch),
    ),
    cmd(
      "studio.ai.history",
      "app.command.ai.history",
      ai,
      AiUiOp(@ai.ToggleAiHistory),
    ),
    cmd("studio.run.start", "app.command.run.start", run_group, RunStart),
    cmd("studio.run.stop", "app.command.run.stop", run_group, RunStop),
    cmd("studio.compile.run", "app.command.compile.run", run_group, CompileRun),
    // 模板四件套必须进表：此前处理器在而表里没有——「口算训练营 /
    // 班级小卖部」（提交数据闸门的核心教案）没有任何 UI 入口，是死命令。
    dispatch_cmd(
      "studio.template.hello",
      "app.templates.hello",
      tmpl,
      NewProjectRequested(0),
    ),
    dispatch_cmd(
      "studio.template.roll_call",
      "app.templates.roll_call",
      tmpl,
      NewProjectRequested(1),
    ),
    dispatch_cmd(
      "studio.template.drill",
      "app.templates.drill",
      tmpl,
      NewProjectRequested(2),
    ),
    dispatch_cmd(
      "studio.template.store",
      "app.templates.store",
      tmpl,
      NewProjectRequested(3),
    ),
    // 新建工程（folder projects）：服务流消息经**效果派发**回程序环
    // （update_with_services 的臂接住），纯链没有目录对话框。
    dispatch_cmd(
      "studio.file.new",
      "app.command.file.new",
      file,
      NewProjectRequested(-1),
    ),
    cmd("studio.file.save", "app.command.file.save", file, SaveRequested),
    cmd("studio.file.open", "app.command.file.open", file, OpenRequested),
    cmd("studio.file.export", "app.command.file.export", file, ExportRequested),
    cmd("studio.preview", "app.preview.title", view, SetMode(ModePreview)),
    cmd("studio.help", "app.help.title", view, SetMode(ModeHelp)),
    cmd(
      "studio.settings",
      "app.command.settings",
      file,
      AiUiOp(@ai.ToggleSettings),
    ),
    cmd("studio.lang.switch", "app.command.lang.switch", file, SwitchLanguage),
    // 插件管理面板（独立模态）：**命令面板入口**。
    //
    // 为什么必须有命令入口：设置面板里也放了一个入口，但设置面板内容
    // 超长，插件那一组在**滚动区下方**——web 端实测点不到（语义节点
    // 落在视口外，点击落空）。命令面板不受滚动影响，是可靠入口。
    //
    // **放在表末**：命令表的下标被回归测试逐条钉住（`commands[21]` 等），
    // 插在中间会打乱一串断言。末尾追加只影响最后一条。
    cmd(
      "studio.plugin.manager",
      "app.plugin.manager.title",
      "app.command.group.plugin",
      PluginManagerOpen,
    ),
  ]
}

///|
/// 静态消息命令：走纯更新通道。
fn cmd(
  id : String,
  label_key : String,
  group_key : String,
  msg : Msg,
) -> @wb.CommandContribution[StudioCtx, Msg] {
  { id, label_key, group_key, run: _ => @wb.Apply(msg), }
}

///|
/// 依赖当前状态（Model）的消息。
fn cmd_with(
  id : String,
  label_key : String,
  group_key : String,
  msg_of : (StudioCtx) -> Msg,
) -> @wb.CommandContribution[StudioCtx, Msg] {
  { id, label_key, group_key, run: ctx => @wb.Apply(msg_of(ctx)), }
}

///|
/// 副作用消息（服务流）：效果派发回程序环，与点按钮同一状态转移。
fn dispatch_cmd(
  id : String,
  label_key : String,
  group_key : String,
  msg : Msg,
) -> @wb.CommandContribution[StudioCtx, Msg] {
  { id, label_key, group_key, run: _ => @wb.Dispatch(msg), }
}

///|
/// 命令面板描述符：跳过 `label_key == ""` 的内部命令，其余按注册顺序渲染
/// （顺序即旧命令表的顺序——过滤测试与用户肌肉记忆都依赖它）。
pub fn studio_commands(t : @i18n.Translator) -> Array[StudioCommand] {
  let commands : Array[StudioCommand] = []
  for contribution in studio_command_registry() {
    if contribution.label_key != "" {
      commands.push({
        id: contribution.id,
        label: text(t, contribution.label_key),
        group: text(t, contribution.group_key),
        hint: "",
      })
    }
  }
  commands
}

///|
/// Studio 命令过滤：查询为空时全部；否则按标签/分组子串匹配（大小写不敏感）。
pub fn filter_studio_commands(
  commands : Array[StudioCommand],
  query : String,
) -> Array[StudioCommand] {
  let trimmed = query.trim().to_owned()
  if trimmed == "" {
    return commands
  }
  let needle = lowercase(trimmed)
  let matched : Array[StudioCommand] = []
  for command in commands {
    if lowercase(command.label).contains(needle) ||
      lowercase(command.group).contains(needle) {
      matched.push(command)
    }
  }
  matched
}

///|
fn lowercase(text : String) -> String {
  let buf = StringBuilder()
  for c in text {
    let code = c.to_int()
    if code >= 0x41 && code <= 0x5A {
      buf.write_char((code + 0x20).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// 插件行（G7.3）：名称 + 一句话职责 + 启用/禁用切换按钮。
fn plugin_row(
  model : Model,
  t : @i18n.Translator,
  id : String,
) -> @moui.View[Msg] {
  let name_key = match id {
    "ai" => "app.plugin.ai"
    "terminal" => "app.plugin.terminal"
    _ => "app.plugin.markdown"
  }
  let summary_key = match id {
    "ai" => "app.plugin.ai.summary"
    "terminal" => "app.plugin.terminal.summary"
    _ => "app.plugin.markdown.summary"
  }
  let active = plugin_active(model, id)
  @views.row(
    [
      @views.column(
        [
          @views.text(
            text(t, name_key),
            theme=@chrome.studio_theme(),
            width=220.0,
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_text()),
          @views.text(
            text(t, summary_key),
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
        on_click=TogglePlugin(id),
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
/// 快捷键行（G7.4）：操作描述 + 按键组合的只读表格行。
fn shortcut_row(
  t : @i18n.Translator,
  label_key : String,
  keys : String,
) -> @moui.View[Msg] {
  @views.row(
    [
      @views.text(
        text(t, label_key),
        theme=@chrome.studio_theme(),
        width=180.0,
        height=16.0,
        align=TextStart,
      ).foreground(@chrome.ide_text()),
      @views.spacer(min_length=6.0, weight=1.0),
      @views.container(
        @views.text(
          keys,
          theme=@chrome.studio_theme(),
          role=Mono,
          width=120.0,
          height=16.0,
          align=TextCenter,
        ).foreground(@chrome.ide_text_faint()),
        background=@chrome.ide_panel(),
        width=128.0,
        height=20.0,
        padding=0.0,
      ),
    ],
    spacing=8.0,
    align=Center,
  ).frame(width=392.0, height=22.0)
}
