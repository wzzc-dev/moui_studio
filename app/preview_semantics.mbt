///|
/// 提交请求装配(纯):工程/帧/选中/草稿逐项把关,全部就绪才给出补丁
/// 请求。None = 没有可提交的东西(静默无操作);Some(Err) = 显式报错。
pub fn semantic_commit_request(
  model : Model,
) -> Result[SemanticPatchRequest, String]? {
  let project = match active_project_of(model) {
    Some(project) => project
    None => return Some(Err("先导入一个 MoonBit 工程"))
  }
  let frame = match model.preview_frame {
    Some(frame) => frame
    None => return Some(Err("还没有预览画面——先构建一次预览"))
  }
  let index = match model.selected_semantic {
    Some(index) => index
    None => return Some(Err("先在预览画布上点选一个元素"))
  }
  let nodes = @run.semantic_hit_nodes(frame)
  if index < 0 || index >= nodes.length() {
    return Some(
      Err("选中的元素已不存在(预览刷新后失效),请重新点选"),
    )
  }
  let node = nodes[index]
  if node.label == "" {
    return Some(Err("这个元素没有可编辑的文本"))
  }
  if model.semantic_draft == "" || model.semantic_draft == node.label {
    return None
  }
  // 程序包的 .mbt 源文件(绝对路径;来自扫描快照,不重新列目录)
  let program_rel = match project.scanned.program_packages {
    [first, ..] => first
    [] => return Some(Err("该工程没有逻辑入口包"))
  }
  let paths : Array[String] = []
  for pkg in project.scanned.packages {
    if pkg.rel_path == program_rel {
      for name in pkg.files {
        if name.has_suffix(".mbt") {
          paths.push("\{project.root}/\{program_rel}/\{name}")
        }
      }
    }
  }
  if paths.length() == 0 {
    return Some(Err("程序包里没有 .mbt 源文件"))
  }
  Some(
    Ok(@run.SemanticPatchRequest::{
      paths,
      label: node.label,
      new_text: model.semantic_draft,
    }),
  )
}
