///|
/// MoUI Studio 预览域·视图贡献(S3b-2 出壳)。
///
/// 与壳的契约(无状态视图先例,markdown/terminal 同款):本包只提供
/// `[Msg]` 泛型视图构建器——状态以只读参数进入,行为以 `on_*~` 回调
/// 注入;壳负责组装与消息路由。标签文案经 `t` 注入,不持有 i18n 状态。

///|
/// 画布重放:解析好的 DrawCommand 按序推回 PaintContext,选中节点以
/// 强调色描边高亮(画在重放内容之上)。画布 1:1(帧坐标),超出交给
/// 外层滚动。点选 = 命中取最深(最后一个匹配),下标交回调。
pub fn[Msg] preview_replay_canvas(
  frame : PreviewFrame,
  selected_index : Int32?,
  pane_width : Double,
  on_select~ : (Int32) -> Msg,
) -> @moui.View[Msg] {
  let canvas_width = frame.width.max(1.0)
  let canvas_height = frame.height.max(1.0)
  let nodes = semantic_hit_nodes(frame)
  let selected = match selected_index {
    Some(index) =>
      if index >= 0 && index < nodes.length() {
        Some(nodes[index])
      } else {
        None
      }
    None => None
  }
  @views.container(
    @views.measured_canvas(
      measure=fn(_constraints, _text_system) {
        @geometry.Size::new(width=canvas_width, height=canvas_height)
      },
      draw=fn(ctx, _frame) {
        // 重放:解析好的 DrawCommand 按序推回 PaintContext
        for command in frame.commands {
          ctx.commands.push(command)
        }
        // 选中高亮:强调色描边(画在重放内容之上)
        match selected {
          Some(node) =>
            ctx.commands.push(
              @core.StrokeRect(
                @geometry.Rect::new(
                  x=node.frame.origin.x - 2.0,
                  y=node.frame.origin.y - 2.0,
                  width=node.frame.size.width + 4.0,
                  height=node.frame.size.height + 4.0,
                ),
                @chrome.ide_accent(),
                2.0,
              ),
            )
          None => ()
        }
      },
      semantics_label="preview-canvas",
    ).on_tap_with_frame(fn(position, tap_frame) {
      // 画布局部坐标 = 帧坐标(1:1);命中取最深(最后一个匹配)
      let x = position.x - tap_frame.origin.x
      let y = position.y - tap_frame.origin.y
      on_select(semantic_hit_index(nodes, x, y))
    }),
    background=@chrome.ide_editor_background(),
    width=canvas_width.min(pane_width - 2.0).max(1.0),
    height=canvas_height,
    padding=0.0,
  )
}

///|
/// 属性条(M1-3):选中语义节点的信息 + label 字面量编辑 + 提交。
/// 未选中时显示占位文案;编辑与提交经回调注入。
pub fn[Msg] semantic_property_strip(
  frame : PreviewFrame?,
  selected_index : Int32?,
  draft : String,
  t : @i18n.Translator,
  height : Double,
  on_label_input~ : (String) -> Msg,
  on_label_commit~ : Msg,
) -> @moui.View[Msg] {
  let selected = match selected_index {
    Some(index) =>
      match frame {
        Some(frame) => {
          let nodes = semantic_hit_nodes(frame)
          if index >= 0 && index < nodes.length() {
            Some(nodes[index])
          } else {
            None
          }
        }
        None => None
      }
    None => None
  }
  let rows : Array[@moui.View[Msg]] = [
    @views.padding_xy(
      @views.text(
        text(t, "app.project.props_title"),
        theme=@chrome.studio_theme(),
        width=196.0,
        height=18.0,
        align=TextStart,
      ).foreground(@chrome.ide_text()),
      horizontal=12.0,
      vertical=8.0,
    ),
  ]
  match selected {
    None =>
      rows.push(
        @views.padding_xy(
          @views.text(
            text(t, "app.project.props_none"),
            theme=@chrome.studio_theme(),
            width=196.0,
            height=34.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_faint()),
          horizontal=12.0,
          vertical=0.0,
        ),
      )
    Some(node) => {
      rows.push(
        @views.padding_xy(
          @views.text(
            text_with(t, "app.project.props_role", [("a", node.role)]),
            theme=@chrome.studio_theme(),
            width=196.0,
            height=16.0,
            align=TextStart,
          ).foreground(@chrome.ide_text_muted()),
          horizontal=12.0,
          vertical=0.0,
        ),
      )
      rows.push(
        @views.padding_xy(
          @views.text_field(
            draft,
            on_input=text => on_label_input(text),
            placeholder=text(t, "app.project.props_label_hint"),
            variant=Outline,
            width=196.0,
            height=@chrome.FIELD_HEIGHT,
          ),
          horizontal=12.0,
          vertical=6.0,
        ),
      )
      rows.push(
        @views.container(
          @views.center(
            @views.text(
              text(t, "app.project.props_apply"),
              theme=@chrome.studio_theme(),
              width=80.0,
              height=18.0,
            ),
            width=196.0,
            height=28.0,
          ),
          background=@chrome.ide_accent(),
          corner_radius=4.0,
          width=196.0,
          height=28.0,
          padding=0.0,
        ).on_tap(on_label_commit),
      )
    }
  }
  @views.container(
    @views.scroll_view(
      @views.column(rows, spacing=4.0),
      width=220.0,
      height~,
      shows_indicator=true,
    ),
    background=@chrome.ide_panel(),
    width=220.0,
    height~,
    padding=0.0,
  )
}

///|
/// 标签文案查找(i18n 目录键;包内局部助手,plugins/project 同款)。
fn text(t : @i18n.Translator, key : String) -> String {
  t.translate(key)
}

///|
/// 带参插值文案。
fn text_with(
  t : @i18n.Translator,
  key : String,
  values : Array[(String, String)],
) -> String {
  t.translate(key, values~)
}
