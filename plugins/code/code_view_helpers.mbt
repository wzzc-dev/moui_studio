///|
/// 工程文件编辑器的 mono 字体（与 IR 编辑面同一套；S7c 自壳移入代码插件）。
pub fn mono_code_font() -> @text.FontSpec {
  @text.FontSpec::new(families=@text.FontFamilyStack::monospace(), size=13.0)
}

///|
/// tab 标签：rel 末段（S7c 自壳移入代码插件；脏点由视图层另挂）。
pub fn file_tab_label(rel : String) -> String {
  let mut label = rel
  for part in rel.split("/") {
    label = part.to_owned()
  }
  label
}
