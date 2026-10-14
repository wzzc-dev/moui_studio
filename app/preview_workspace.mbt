///|
/// 预览工作区(M1-2):FramePreview 构建回执的 headless 帧重放画布。
///
/// 数据流:构建(BkFramePreview = `moon run .studio/preview`)→ 哨兵协议
/// 解析 → `PreviewFrame` → 本视图把重建的 `DrawCommand` 序列**按序推回
/// PaintContext**(PaintContext 本就是 DrawCommand 收集器,重放零转换);
/// 未知 op 在画布上方的横幅里诚实列出,不静默丢。
///
/// 坐标 1:1(设计坐标 640×480,画布按帧尺寸给);缩放/模式二/三状态条
/// 在后续里程碑接。

///|
/// 预览工作区主体(ide_root 的 workspace_content 分派)。
pub fn preview_workspace(
  model : Model,
  t : @i18n.Translator,
  width : Double,
  height : Double,
) -> @moui.View[Msg] {
  match active_project_of(model) {
    None =>
      @views.container(
        @chrome.empty_hint(text(t, "app.project.no_project"), width, height),
        background=@chrome.ide_editor_background(),
        width~,
        height~,
        padding=0.0,
      )
    Some(project) => {
      // 模式条(M2-2/M3):画布快览 / 网页实时 / 独立运行。
      // Web 需要静态服务 + webview 控制器(native 入口),缺失则禁用。
      let controls = preview_web_controls()
      let web_available = controls.port > 0 &&
        preview_web_controller() is Some(_)
      let mode_strip = @views.row(
        [
          mode_strip_button(
            text(t, "app.project.mode.frame"),
            model.preview_mode() is PmFrame,
            RunUiOp(@run.SetPreviewMode(false)),
          ),
          mode_strip_button(
            text(t, "app.project.mode.web"),
            model.preview_mode() is PmWeb,
            if web_available {
              RunUiOp(@run.SetPreviewMode(true))
            } else {
              SetNotice(text(t, "app.project.preview_web_unavailable"))
            },
          ),
          mode_strip_button(
            text(t, "app.project.mode.native"),
            false,
            ProjectBuildRun(@build.BkRunNative),
          ),
          // 外部改动重载（M8）：手动刷新入口——外部编辑器改了 form.mbt
          // 后点这里读取比对，提示并重载设计器会话。只在布局设计器
          // 会话打开时显示（无会话时无事可查）。
          if model.form_designer is Some(_) {
            mode_strip_button(
              text(t, "app.project.external_check"),
              false,
              FormDesignExternalCheck,
            )
          } else {
            @views.text("", width=1.0, height=1.0)
          },
          // 布局页签（M4 收尾）：画布/布局二分，只属于模式一。
          if model.preview_mode() is PmFrame {
            mode_strip_button(
              text(t, "app.project.design_tab"),
              model.preview_design_open,
              SetPreviewDesignOpen(!model.preview_design_open),
            )
          } else {
            @views.text("", width=1.0, height=1.0)
          },
        ],
        spacing=4.0,
        align=Center,
      )
      let head = @views.container(
        @views.row(
          [
            @views.text(
              project.module_name,
              theme=@chrome.studio_theme(),
              width=(width - 420.0).max(80.0),
              height=20.0,
              align=TextStart,
            ).foreground(@chrome.ide_text()),
            mode_strip,
            @views.text(
              if model.build_busy {
                text(t, "app.project.preview_building")
              } else {
                text(t, "app.project.preview_rebuild_hint")
              },
              theme=@chrome.studio_theme(),
              width=(width - 260.0).max(80.0),
              height=18.0,
              align=TextEnd,
            ).foreground(@chrome.ide_text_muted()),
            icon_button(
              Save,
              text(t, "app.project.preview_rebuild"),
              false,
              ProjectBuildRun(BkFramePreview),
              24.0,
              24.0,
              12.0,
            ),
          ],
          spacing=8.0,
          align=Center,
        ),
        background=@chrome.ide_panel(),
        width~,
        height=40.0,
        padding=0.0,
      )
      // 布局设计器区（M4 收尾）：会话在 = 画布；不在 = 打开入口。
      let designer_area = fn(area_height : Double) -> @moui.View[Msg] {
        let area_width = (width - 226.0).max(120.0)
        match model.form_designer {
          Some(session) =>
            form_design_canvas(
              session,
              model.selected_form_control,
              area_width,
              area_height,
            )
          None =>
            @views.container(
              @views.column(
                [
                  @views.text(
                    text(t, "app.project.design_empty"),
                    theme=@chrome.studio_theme(),
                    width=(area_width - 40.0).max(80.0),
                    height=24.0,
                    align=TextCenter,
                  ).foreground(@chrome.ide_text_muted()),
                  @views.button(
                    text(t, "app.project.design_open"),
                    on_click=FormDesignOpen,
                    variant=Primary,
                  ),
                ],
                spacing=12.0,
                align=Center,
              ),
              width=area_width,
              height~,
              padding=0.0,
            )
        }
      }
      let body = if model.preview_design_open {
        // 布局设计器不依赖预览帧：未构建也能进入（M4 收尾）
        designer_area(height)
      } else {
        match model.preview_frame {
          None =>
            @views.container(
              @views.column(
                [
                  @views.text(
                    text(t, "app.project.preview_empty"),
                    theme=@chrome.studio_theme(),
                    width=(width - 40.0).max(80.0),
                    height=24.0,
                    align=TextCenter,
                  ).foreground(@chrome.ide_text_muted()),
                  @views.button(
                    text(t, "app.project.preview_build_now"),
                    on_click=ProjectBuildRun(BkFramePreview),
                    variant=Primary,
                  ),
                ],
                spacing=12.0,
                align=Center,
              ),
              width~,
              height~,
              padding=0.0,
            )
          Some(frame) => {
            // 未知 op 横幅:诚实列出,不静默
            let warning = if frame.unknown_ops.length() > 0 {
              @views.container(
                @views.padding_xy(
                  @views.text(
                    @chrome.fit_label(
                      text_with(t, "app.project.preview_unknown_ops", [
                        ("a", frame.unknown_ops.length().to_string()),
                      ]),
                      (width - 260.0).max(60.0),
                    ),
                    theme=@chrome.studio_theme(),
                    width=(width - 260.0).max(60.0),
                    height=18.0,
                    align=TextStart,
                  ).foreground(@chrome.ide_text_muted()),
                  horizontal=12.0,
                  vertical=4.0,
                ),
                background=@chrome.ide_panel(),
                width~,
                height=26.0,
                padding=0.0,
              )
            } else {
              @views.text("", width=1.0, height=1.0)
            }
            let canvas_width = (width - 226.0).max(120.0)
            let canvas_area = if model.preview_mode() is PmWeb {
              match preview_web_controller() {
                Some(controller) =>
                  @webview_views.web_view(
                    controller~,
                    title="preview",
                    width=Some(canvas_width),
                    height=Some(frame.height),
                  )
                None =>
                  @views.container(
                    @chrome.empty_hint(
                      text(t, "app.project.preview_web_unavailable"),
                      canvas_width,
                      height,
                    ),
                    width=canvas_width,
                    height~,
                    padding=0.0,
                  )
              }
            } else if model.preview_design_open {
              // 布局设计器（M4 收尾）：拖拽/保存 → span 补丁写 form.mbt
              designer_area(frame.height)
            } else {
              preview_replay_canvas(model, frame, canvas_width)
            }
            let canvas_column = @views.column(
              [warning, canvas_area],
              spacing=0.0,
            ).frame(width=canvas_width, height~)
            @views.row(
              [canvas_column, semantic_property_strip(model, t, height)],
              spacing=0.0,
              align=Start,
            ).frame(width~, height~)
          }
        }
      }
      @views.container(
        @views.column([head, body], spacing=0.0).frame(width~, height~),
        background=@chrome.ide_editor_background(),
        width~,
        height~,
        padding=0.0,
      )
    }
  }
}

///|
pub fn preview_replay_canvas(
  model : Model,
  frame : PreviewFrame,
  pane_width : Double,
) -> @moui.View[Msg] {
  @run.preview_replay_canvas(frame, model.selected_semantic, pane_width, on_select=index => {
    SelectSemanticNode(index)
  })
}

///|
pub fn semantic_property_strip(
  model : Model,
  t : @i18n.Translator,
  height : Double,
) -> @moui.View[Msg] {
  @run.semantic_property_strip(
    model.preview_frame,
    model.selected_semantic,
    model.semantic_draft,
    t,
    height,
    on_label_input=draft => SemanticLabelInput(draft),
    on_label_commit=SemanticLabelCommit,
  )
}

///|
/// 模式条按钮:文字 + 高亮(选中 = 选中底色 + 强调文字)。
fn mode_strip_button(
  label : String,
  selected : Bool,
  on_click : Msg,
) -> @moui.View[Msg] {
  @views.container(
    @views.center(
      @views.text(label, theme=@chrome.studio_theme(), width=88.0, height=16.0).foreground(
        if selected {
          @chrome.ide_text()
        } else {
          @chrome.ide_text_muted()
        },
      ),
      width=96.0,
      height=24.0,
    ),
    background=if selected {
      @chrome.ide_selection()
    } else {
      @chrome.ide_panel()
    },
    corner_radius=4.0,
    width=96.0,
    height=24.0,
    padding=0.0,
  ).on_tap(on_click)
}
