///|
/// M4：面板贡献表——底栏页签、徽标、终端开关语义、插件门控与左右栏正文
/// 分派都从 `studio_panels` 派生，视图只做查表。

///|
fn panel_ids(model : Model, location : @wb.PanelLocation) -> Array[String] {
  let ids : Array[String] = []
  for panel in @wb.panels_at(studio_panels(model), location) {
    ids.push(panel.id)
  }
  ids
}

///|
fn panel_by_id(
  panels : Array[@wb.PanelContribution[StudioCtx, Msg]],
  id : String,
) -> @wb.PanelContribution[StudioCtx, Msg]? {
  for panel in panels {
    if panel.id == id {
      return Some(panel)
    }
  }
  None
}

///|
fn selected_panel_id(model : Model, location : @wb.PanelLocation) -> String {
  let ctx : StudioCtx = { model, t: translator(model), }
  match @wb.selected_panel(studio_panels(model), location, ctx) {
    Some(panel) => panel.id
    None => ""
  }
}

///|
test "panel registry:底栏页签顺序与五页签切换" {
  let mut model = initial_model()
  let ids = [
    "bottom.audit", "bottom.console", "bottom.problems", "bottom.search", "bottom.terminal",
  ]
  let registered = panel_ids(model, @wb.PanelBottom)
  assert_eq(registered.length(), ids.length())
  for index, id in ids {
    assert_eq(registered[index], id)
    let ctx : StudioCtx = { model, t: translator(model), }
    let panels = @wb.panels_at(studio_panels(model), @wb.PanelBottom)
    let panel = panel_by_id(panels, id).unwrap()
    let next = apply_shell(model, (panel.on_select)(ctx))
    assert_eq(selected_panel_id(next, @wb.PanelBottom), id)
    model = next
  }
}

///|
test "panel registry:底栏徽标来自各自数据源" {
  let warn : AuditEntry = {
    kind: AuditWarn,
    seq: 9,
    text: "待确认",
    detail: "",
    stack: "",
    settled: false,
    settled_note: "",
  }
  let hit : SearchHit = { rel: "app/app.mbt", line: 3, preview: "fn main", }
  let model = { ..initial_model(), audit_entries: [warn], search_hits: [hit], }
  let ctx : StudioCtx = { model, t: translator(model), }
  let panels = @wb.panels_at(studio_panels(model), @wb.PanelBottom)
  assert_eq((panels[0].badge)(ctx), pending_side_effects(model))
  assert_eq((panels[0].badge)(ctx), 1)
  assert_eq((panels[1].badge)(ctx), model.log_lines.length())
  assert_eq((panels[2].badge)(ctx), problem_rows(model, ctx.t).length())
  assert_eq((panels[3].badge)(ctx), model.search_hits.length())
  assert_eq((panels[4].badge)(ctx), 0)
}

///|
test "panel registry:终端页签再点关闭,关闭态再点重开" {
  let model = initial_model()
  let panels = @wb.panels_at(studio_panels(model), @wb.PanelBottom)
  let terminal = panel_by_id(panels, "bottom.terminal").unwrap()
  let idle = { ..model, bottom_tab: BtConsole, }
  let idle_ctx : StudioCtx = { model: idle, t: translator(idle), }
  assert_false((terminal.selected)(idle_ctx))
  match (terminal.on_select)(idle_ctx) {
    SetBottomTab(BtTerminal) => ()
    _ => fail("未选中的终端页签点击应选中")
  }
  let selected = { ..model, bottom_tab: BtTerminal, }
  selected.terminal_open = true
  let selected_ctx : StudioCtx = { model: selected, t: translator(selected), }
  assert_true((terminal.selected)(selected_ctx))
  match (terminal.on_select)(selected_ctx) {
    TerminalTabClose => ()
    _ => fail("已选中的终端页签再点应关闭")
  }
  let closed = update_with_services(
      selected,
      TerminalTabClose,
      @services.AppServices::new(),
    ).0
  assert_false(closed.terminal_open)
  assert_false(closed.bottom_open)
  assert_true(closed.bottom_tab is BtConsole)
  assert_eq(selected_panel_id(closed, @wb.PanelBottom), "bottom.console")
  // 关闭态再点同一页签 = 重开（on_select 回到选中语义）
  let closed_ctx : StudioCtx = { model: closed, t: translator(closed), }
  match (terminal.on_select)(closed_ctx) {
    SetBottomTab(BtTerminal) => ()
    _ => fail("关闭态的终端页签点击应重开")
  }
  let reopened = apply_shell(closed, (terminal.on_select)(closed_ctx))
  assert_true(reopened.terminal_open)
  assert_eq(selected_panel_id(reopened, @wb.PanelBottom), "bottom.terminal")
}

///|
test "panel registry:终端插件缺席即不注册" {
  let model = initial_model()
  assert_true(panel_ids(model, @wb.PanelBottom).contains("bottom.terminal"))
  let services = @services.AppServices::new()
  let terminal_off = update_with_services(
      model,
      TogglePlugin("terminal"),
      services,
    ).0
  assert_false(
    panel_ids(terminal_off, @wb.PanelBottom).contains("bottom.terminal"),
  )
}
