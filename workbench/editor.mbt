///|
/// 文档编辑宿主：编辑/光标/事务消息都按文档 id 定向，而不是按活动下标。
/// 关闭或重排 tab 后，排队事件不会被投到另一篇文档上。
pub(all) struct EditorHost[Msg] {
  edit : (String) -> Msg
  caret : (Int32, @core.TextRange?) -> Msg
  markdown : (@moui_richtext.MarkdownEditTransaction) -> Msg
  save : Msg
  close : Msg
}

///|
/// 编辑面贡献：按文档类型认领渲染权。`priority` 只在多个 provider 同时
/// accepts 时裁决，同优先级先注册者胜出。
pub(all) struct EditorProvider[Ctx, Msg] {
  id : String
  priority : Int32
  accepts : (Ctx, Document) -> Bool
  render : (Ctx, DocumentEntry, EditorHost[Msg], Double, Double) -> @moui.View[
    Msg,
  ]
}

///|
/// 解析顺序：指定 provider 且认领 → 认领者中优先级最高 → 空编辑面。
pub fn[Ctx, Msg] resolve_provider(
  providers : Array[EditorProvider[Ctx, Msg]],
  ctx : Ctx,
  doc : Document,
  preferred : String,
) -> EditorProvider[Ctx, Msg]? {
  if preferred != "" {
    for provider in providers {
      if provider.id == preferred && (provider.accepts)(ctx, doc) {
        return Some(provider)
      }
    }
  }
  let mut best : EditorProvider[Ctx, Msg]? = None
  for provider in providers {
    if (provider.accepts)(ctx, doc) {
      match best {
        None => best = Some(provider)
        Some(current) =>
          if provider.priority > current.priority {
            best = Some(provider)
          }
      }
    }
  }
  best
}
