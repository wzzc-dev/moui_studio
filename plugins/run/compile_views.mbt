///|
/// 编译轨视图（S7d 出壳）：真编译动作条 + 报告卡（工具链退出码 + 结构化诊断 +
/// 原始输出 + 产物旁路）+ 忙态进度卡。「编译失败不静默降级」的界面半边。
///
/// 纯视图，不读壳 Model：状态用 `CompileViewsParams[Msg]` 注入，动作走 on_*
/// 回调；产物旁路上的幽灵图标按钮因携带壳状态提示（HoverHint），由壳以
/// `ghost_icon` 回调构建后注入。

///|
/// 编译轨视图参数：5 个 compile_* 状态 + 动作回调 + 幽灵图标按钮构造器。
pub(all) struct CompileViewsParams[Msg] {
  busy : Bool
  track_available : Bool
  output_open : Bool
  progress : Array[@export.CompileProgress]
  report : @export.CompileReport?
  /// 产物旁路上的幽灵图标按钮（copy/reveal），壳用 ghost_icon_button 构造
  /// （要发壳的 HoverHint）；固定尺寸 28×22 / 图标 13 / elevated 面。
  ghost_icon : (@style.IconName, String, Bool, Msg) -> @moui.View[Msg]
  on_run : Msg
  on_cancel : Msg
  on_toggle_output : Msg
  on_run_artifact : (String) -> Msg
  on_copy_path : (String) -> Msg
  on_reveal : (String) -> Msg
  on_jump : (Int32) -> Msg
}

///|
/// 某一步在进度序列里的归并态：Some(true)=进行中、Some(false)=已完成、
/// None=未开始。后到的覆盖先到（finished 最终胜出）。
pub fn compile_step_state(
  progress : Array[@export.CompileProgress],
  phase : @export.CompilePhase,
) -> Bool? {
  let mut state : Bool? = None
  for item in progress {
    if item.phase.tag() == phase.tag() {
      state = Some(item.started)
    }
  }
  state
}

///|
/// (已完成数, 总步数)。
pub fn compile_progress_counts(
  progress : Array[@export.CompileProgress],
) -> (Int32, Int32) {
  let mut done = 0
  for phase in @export.compile_phases() {
    match compile_step_state(progress, phase) {
      Some(false) => done = done + 1
      _ => ()
    }
  }
  (done, @export.compile_phase_total())
}

///|
/// 当前进行中的阶段（无则 None）。
pub fn compile_active_phase(
  progress : Array[@export.CompileProgress],
) -> @export.CompilePhase? {
  let mut active : @export.CompilePhase? = None
  for phase in @export.compile_phases() {
    match compile_step_state(progress, phase) {
      Some(true) => active = Some(phase)
      _ => ()
    }
  }
  active
}

///|
/// 编译轨头部（触发条 + 报告卡）：预览视图与运行视图共用同一入口。
pub fn[Msg] compiled_run_header(
  p : CompileViewsParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  @views.column([compile_action_bar(p, t), compile_report_card(p, t)])
}

///|
/// 真编译动作条：显式触发（切轨不隐式编译）+ 忙态提示 + 当前轨说明。
fn[Msg] compile_action_bar(
  p : CompileViewsParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let trigger = if p.busy {
    // 编译进行中 = 停止（不是再点一次编译）：清报告与忙态、不切轨、不自动
    // 回退解释轨（与既有语义一致）。
    @views.button(
      t.translate("app.compile.cancel"),
      on_click=p.on_cancel,
      variant=Tonal,
      width=140.0,
    )
  } else {
    @views.button(
      t.translate("app.compile.ok"),
      on_click=p.on_run,
      variant=Primary,
      width=140.0,
    )
  }
  @views.row(
    [
      trigger,
      @views.text(
        if p.track_available {
          t.translate("app.track.compile_note")
        } else {
          t.translate("app.track.unavailable_web")
        },
        role=Caption,
        width=420.0,
        align=TextStart,
      ),
    ],
    spacing=8.0,
    align=Center,
  )
}

///|
/// 真编译报告卡：无报告且不在编译时渲染空视图（调用方不必分支）。
fn[Msg] compile_report_card(
  p : CompileViewsParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  if p.busy {
    return compile_progress_card(p, t)
  }
  match p.report {
    None => @views.text("")
    Some(report) => {
      let badge = @views.badge(
        theme=@chrome.studio_theme(),
        if report.ok {
          t.translate("app.compile.ok")
        } else {
          t.translate("app.compile.failed")
        },
        tone=if report.ok {
          @style.BadgeTone::Success
        } else {
          @style.BadgeTone::Danger
        },
        width=140.0,
        height=24.0,
      )
      let rows : Array[@moui.View[Msg]] = [
        @views.row(
          [
            badge,
            @views.text(
              "\{t.translate("app.compile.target")}：\{report.target}",
              width=160.0,
            ),
            @views.text(
              "\{t.translate("app.compile.exit_code")}：\{report.exit_code}",
              width=160.0,
            ),
          ],
          spacing=8.0,
          align=Center,
        ),
      ]
      let errors = report.errors()
      if errors.length() > 0 {
        rows.push(
          @views.text(t.translate("app.compile.diagnostics"), role=Subtitle),
        )
        rows.push(@views.text(t.translate("app.compile.jump"), role=Caption))
        for diagnostic in errors {
          rows.push(diagnostic_row(p, diagnostic, t))
        }
      }
      // 产物段：真编译「编出了什么」的事实面。
      rows.push(
        @views.row(
          [
            @views.text(t.translate("app.compile.artifacts"), role=Subtitle),
            @views.badge(
              theme=@chrome.studio_theme(),
              report.artifacts.length().to_string(),
              tone=if report.artifacts.length() > 0 {
                @style.BadgeTone::Success
              } else {
                @style.BadgeTone::Neutral
              },
              width=48.0,
              height=20.0,
            ),
          ],
          spacing=8.0,
          align=Center,
        ),
      )
      if report.artifacts.length() == 0 {
        rows.push(
          @views.text(t.translate("app.compile.artifacts.none"), role=Caption),
        )
      } else {
        rows.push(
          @views.text(t.translate("app.compile.open_hint"), role=Caption),
        )
        for artifact in report.artifacts {
          rows.push(artifact_row(p, artifact, t))
        }
      }
      if report.work_root != "" {
        // 工作目录给完整读数（中间省略，与产物行同一把尺子）。
        rows.push(
          @views.row(
            [
              @views.text(
                t.translate("app.compile.work_root"),
                role=Caption,
                width=72.0,
              ),
              @views.text(
                middle_ellipsis(report.work_root, 480.0),
                role=Mono,
                width=480.0,
                align=TextStart,
              ),
              (p.ghost_icon)(
                Clipboard,
                t.translate("app.compile.artifact.copy"),
                false,
                (p.on_copy_path)(report.work_root),
              ),
              (p.ghost_icon)(
                FolderOpen,
                t.translate("app.compile.artifact.reveal"),
                false,
                (p.on_reveal)(report.work_root),
              ),
            ],
            spacing=6.0,
            align=Center,
          ),
        )
      }
      let output_lines : Array[@moui.View[Msg]] = []
      if p.output_open {
        let output_views : Array[@moui.View[Msg]] = []
        for line in report.output.split("\n") {
          output_views.push(
            @views.text(
              line.to_owned(),
              role=Mono,
              width=548.0,
              align=TextStart,
            ),
          )
        }
        output_lines.push(
          @views.container(
            @views.scroll_view(
              @views.column(output_views),
              width=564.0,
              height=156.0,
              shows_indicator=true,
            ),
            background=@chrome.studio_console_background(),
            corner_radius=4.0,
            padding=8.0,
          ),
        )
      }
      @views.card(
        @views.column(
          [
            @views.column(rows, spacing=6.0),
            @views.row(
              [
                @views.button(
                  t.translate("app.compile.output"),
                  on_click=p.on_toggle_output,
                  variant=Ghost,
                  width=140.0,
                ),
                @views.badge(
                  theme=@chrome.studio_theme(),
                  report.output.split("\n").count().to_string(),
                  tone=@style.BadgeTone::Neutral,
                  width=48.0,
                  height=20.0,
                ),
              ],
              spacing=8.0,
              align=Center,
            ),
            @views.column(output_lines),
          ],
          spacing=6.0,
        ),
        width=600.0,
        padding=10.0,
      )
    }
  }
}

///|
/// 编译进度卡：忙态下代替报告卡（两个读数不同时在场）。七个真实步骤逐格画出
/// ——已完成点满、进行中高亮、未开始暗色。步骤表来自 `@export.compile_phases()`
/// （与 worker 推进度同一张表），不会多画/少画一格。
fn[Msg] compile_progress_card(
  p : CompileViewsParams[Msg],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let (done, total) = compile_progress_counts(p.progress)
  let active = compile_active_phase(p.progress)
  let steps : Array[@moui.View[Msg]] = []
  for phase in @export.compile_phases() {
    steps.push(compile_step_row(phase, p.progress, t))
  }
  let status = match active {
    Some(phase) => t.translate("app.compile.phase.\{phase.tag()}")
    None => t.translate("app.compile.running")
  }
  @views.card(
    @views.column(
      [
        @views.row(
          [
            @views.badge(
              theme=@chrome.studio_theme(),
              t.translate("app.compile.step", values=[
                ("done", done.to_string()),
                ("total", total.to_string()),
              ]),
              tone=@style.BadgeTone::Warning,
              width=140.0,
              height=24.0,
            ),
            @views.text(status, role=Subtitle),
          ],
          spacing=8.0,
          align=Center,
        ),
        @views.column(steps, spacing=4.0),
        @views.text(t.translate("app.track.compile_note"), role=Caption),
      ],
      spacing=8.0,
    ),
    width=600.0,
    padding=10.0,
  )
}

///|
/// 进度里的一步：状态点（完成/进行中/未开始）+ 步骤名 + 状态字。
fn[Msg] compile_step_row(
  phase : @export.CompilePhase,
  progress : Array[@export.CompileProgress],
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let (dot_color, label_color, state_text) = match
    compile_step_state(progress, phase) {
    Some(false) =>
      (
        @chrome.ide_success(),
        @chrome.ide_text(),
        t.translate("app.compile.step_done"),
      )
    Some(true) =>
      (
        @chrome.ide_accent(),
        @chrome.ide_text(),
        t.translate("app.compile.step_active"),
      )
    None => (@chrome.ide_border(), @chrome.ide_text_faint(), "")
  }
  @views.row(
    [
      @views.container(
        @views.text("", width=1.0, height=1.0),
        background=dot_color,
        corner_radius=4.0,
        width=8.0,
        height=8.0,
        padding=0.0,
      ),
      @views.text(
        t.translate("app.compile.phase.\{phase.tag()}"),
        theme=@chrome.studio_theme(),
        width=380.0,
        height=18.0,
        align=TextStart,
      ).foreground(label_color),
      @views.text(
        state_text,
        theme=@chrome.studio_theme(),
        width=80.0,
        height=18.0,
        align=TextEnd,
      ).foreground(
        if dot_color == @chrome.ide_success() {
          @chrome.ide_success()
        } else {
          @chrome.ide_accent()
        },
      ),
    ],
    spacing=8.0,
    align=Center,
  )
}

///|
/// 单条产物行：类型徽标 + 完整路径（中间省略）+ 字节数 + 动作（GUI 多一个
/// 「运行产物」，其余 = 复制路径 / 在文件夹中打开）。
fn[Msg] artifact_row(
  p : CompileViewsParams[Msg],
  artifact : @export.CompileArtifact,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  let path_width = 580.0
  let is_gui = artifact.kind == "native-app"
  let badge_label = if is_gui {
    t.translate("app.compile.artifact.gui")
  } else if artifact.kind == "native-smoke" {
    t.translate("app.compile.artifact.headless")
  } else {
    artifact.label
  }
  let badge_width = if is_gui || artifact.kind == "native-smoke" {
    132.0
  } else {
    104.0
  }
  let actions : Array[@moui.View[Msg]] = []
  if is_gui {
    // 运行产物 = 一键启动（脱离式，Studio 退出不带走导出应用）。
    actions.push(
      @views.button(
        t.translate("app.compile.run_artifact"),
        on_click=(p.on_run_artifact)(artifact.path),
        variant=Primary,
        width=104.0,
        height=22.0,
      ),
    )
  }
  actions.push(
    (p.ghost_icon)(
      Clipboard,
      t.translate("app.compile.artifact.copy"),
      false,
      (p.on_copy_path)(artifact.path),
    ),
  )
  actions.push(
    (p.ghost_icon)(
      FolderOpen,
      t.translate("app.compile.artifact.reveal"),
      false,
      (p.on_reveal)(artifact.path),
    ),
  )
  @views.column(
    [
      @views.row(
        [
          @views.badge(
            theme=@chrome.studio_theme(),
            badge_label,
            tone=if is_gui {
              @style.BadgeTone::Success
            } else if artifact.kind == "native-smoke" {
              @style.BadgeTone::Neutral
            } else {
              @style.BadgeTone::Success
            },
            width=badge_width,
            height=20.0,
          ),
          @views.text(
            middle_ellipsis(artifact.path, path_width - 8.0 - badge_width),
            role=Mono,
            width=path_width - 8.0 - badge_width,
            height=20.0,
            align=TextStart,
          ),
        ],
        spacing=8.0,
        align=Center,
      ),
      @views.row(
        // 动作行：字节数靠左，动作靠右。
        {
          let cells : Array[@moui.View[Msg]] = [
            @views.text(
              byte_size_label(artifact.bytes),
              role=Mono,
              width=72.0,
              height=18.0,
              align=TextStart,
            ).foreground(@chrome.ide_text_faint()),
            @views.spacer(min_length=4.0, weight=1.0),
          ]
          for action in actions {
            cells.push(action)
          }
          cells
        },
        spacing=4.0,
        align=Center,
      ),
    ],
    spacing=2.0,
  )
}

///|
/// 中间省略：保头保尾，中段折叠成 `…`。路径信息分布是「头（哪个卷）+ 尾
/// （哪个文件）」，中段是随机 TMPDIR，尾部省略会切掉最关键的文件名。宽度口径
/// 走 `@chrome.text_estimate_width`（ASCII 7.9 / 全角 13.0）。
pub fn middle_ellipsis(label : String, max_width : Double) -> String {
  if @chrome.text_estimate_width(label) <= max_width {
    return label
  }
  let chars : Array[Char] = []
  for c in label {
    chars.push(c)
  }
  let ellipsis_cost = @chrome.text_estimate_width("…")
  if max_width < ellipsis_cost {
    return ""
  }
  let budget = max_width - ellipsis_cost
  // 两侧交替取字符，head 与 tail 的宽度天然接近。
  let mut head = 0
  let mut tail = 0
  let mut used = 0.0
  let mut take_head = true
  while head + tail < chars.length() {
    let index = if take_head { head } else { chars.length() - 1 - tail }
    let cost = if chars[index].to_int() < 0x80 { 7.9 } else { 13.0 }
    if used + cost > budget {
      break
    }
    used = used + cost
    if take_head {
      head = head + 1
    } else {
      tail = tail + 1
    }
    take_head = !take_head
  }
  // 头段正序 + … + 尾段正序（尾段从 chars.length() - tail 起顺序写出）。
  let buf = StringBuilder()
  let mut i = 0
  while i < head {
    buf.write_char(chars[i])
    i = i + 1
  }
  buf.write_string("…")
  let mut j = chars.length() - tail
  while j < chars.length() {
    buf.write_char(chars[j])
    j = j + 1
  }
  buf.to_string()
}

///|
/// 字节数 → 紧凑可读串（KB/MB 档；源码文件按字节直出）。
fn byte_size_label(bytes : Int32) -> String {
  if bytes <= 0 {
    "—"
  } else if bytes < 1024 {
    "\{bytes} B"
  } else if bytes < 1024 * 1024 {
    "\{(bytes.to_double() / 1024.0).round().to_int()} KB"
  } else {
    "\{(bytes.to_double() / (1024.0 * 1024.0) * 10.0).round().to_int().to_double() / 10.0} MB"
  }
}

///|
/// 单条诊断行：`文件:行:列` + 错误码 + 正文；行号已知时可点击跳回积木。
fn[Msg] diagnostic_row(
  p : CompileViewsParams[Msg],
  diagnostic : @export.CompileDiagnostic,
  t : @i18n.Translator,
) -> @moui.View[Msg] {
  ignore(t)
  let location = if diagnostic.line > 0 {
    "\{short_file(diagnostic.file)}:\{diagnostic.line}:\{diagnostic.column}"
  } else {
    short_file(diagnostic.file)
  }
  let code = if diagnostic.code == "" { "" } else { "[\{diagnostic.code}] " }
  let row = @views.row(
    [
      @views.badge(
        theme=@chrome.studio_theme(),
        diagnostic.severity,
        tone=if diagnostic.severity == "error" {
          @style.BadgeTone::Danger
        } else {
          @style.BadgeTone::Warning
        },
        width=72.0,
        height=20.0,
      ),
      @views.text(location, role=Mono, width=220.0),
      @views.text("\{code}\{diagnostic.text}", role=Mono, width=280.0),
    ],
    spacing=8.0,
    align=Center,
  )
  if diagnostic.line > 0 {
    row.on_tap((p.on_jump)(diagnostic.line))
  } else {
    row
  }
}

///|
/// 诊断里的文件路径可能很长（工作区外 bundle 路径）：只留文件名段。
fn short_file(file : String) -> String {
  let chars : Array[Char] = []
  for c in file {
    chars.push(c)
  }
  let mut slash = -1
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '/' {
      slash = i
    }
    i = i + 1
  }
  if slash < 0 {
    file
  } else {
    let buf = StringBuilder()
    let mut j = slash + 1
    while j < chars.length() {
      buf.write_char(chars[j])
      j = j + 1
    }
    buf.to_string()
  }
}
