///|
/// 命令执行通道：`Apply` 走既有纯更新，`Dispatch` 走效果派发（服务环），
/// `Unavailable` 表示当前状态下不可用。
pub(all) enum CommandAction[Msg] {
  Apply(Msg)
  Dispatch(Msg)
  Unavailable
}

///|
/// `label_key == ""` 表示命令不进命令面板，仅供键盘绑定或内部调用。
pub(all) struct CommandContribution[Ctx, Msg] {
  id : String
  label_key : String
  group_key : String
  run : (Ctx) -> CommandAction[Msg]
}

///|
pub fn[Ctx, Msg] find_command(
  commands : Array[CommandContribution[Ctx, Msg]],
  id : String,
) -> CommandContribution[Ctx, Msg]? {
  for command in commands {
    if command.id == id {
      return Some(command)
    }
  }
  None
}
