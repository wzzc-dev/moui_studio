///|
pub(all) enum PanelLocation {
  PanelLeft
  PanelRight
  PanelBottom
} derive(Eq)

///|
pub extend PanelLocation with Eq::{not_equal, equal}

///|
pub(all) struct PanelContribution[Ctx, Msg] {
  id : String
  location : PanelLocation
  label_key : String
  badge : (Ctx) -> Int32
  selected : (Ctx) -> Bool
  on_select : (Ctx) -> Msg
  render : (Ctx, Double, Double) -> @moui.View[Msg]
}

///|
pub fn[Ctx, Msg] panels_at(
  panels : Array[PanelContribution[Ctx, Msg]],
  location : PanelLocation,
) -> Array[PanelContribution[Ctx, Msg]] {
  let matches : Array[PanelContribution[Ctx, Msg]] = []
  for panel in panels {
    if panel.location == location {
      matches.push(panel)
    }
  }
  matches
}

///|
pub fn[Ctx, Msg] selected_panel(
  panels : Array[PanelContribution[Ctx, Msg]],
  location : PanelLocation,
  ctx : Ctx,
) -> PanelContribution[Ctx, Msg]? {
  for panel in panels {
    if panel.location == location && (panel.selected)(ctx) {
      return Some(panel)
    }
  }
  None
}
