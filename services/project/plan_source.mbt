///|
/// 落盘计划 → 扫描材料（`ProjectSource`）。
///
/// 为什么在 services/project：新建/导入工程时，骨架刚写完就要注册工程记录，
/// 此时重读磁盘要么多一整轮异步 IO、要么和刚落盘的内容不同源。计划本身就是
/// 事实源，按**路径**能推出包清单、包内文件名与程序挂载点。
///
/// 旧口径由调用方读队列下标（`files.get(0)`/`get(1)`）反推工程根与 app 包
/// 清单，再硬编码文件名——骨架多加一个文件（平台入口包、form.mbt）就会
/// 静默改掉工程身份，且新增的包根本不进资源管理器。

///|
/// 计划里的一个包目录（moon.pkg 文本 + 包内文件名 + 是否含程序挂载点）。
priv struct PlanPackage {
  rel : String
  mut pkg_text : String
  mut has_program : Bool
  file_names : Array[String]
}

///|
/// `root` = 工程根绝对路径；`files` = (绝对路径, 内容)。只有带 `moon.pkg`
/// 的目录算包，所以 `.studio/`（快照、预览 harness）不会冒充工程结构。
pub fn project_source_from_plan(
  root : String,
  files : Array[(String, String)],
) -> ProjectSource {
  let groups : Array[PlanPackage] = []
  let prefix_length = root.length() + 1
  for pair in files {
    let (path, content) = pair
    if path.length() <= prefix_length {
      continue
    }
    let rel = path[prefix_length:].to_owned()
    // 根级文件（moon.mod、moui.project.json）不属于任何包
    let dir = match rel.rev_find("/") {
      Some(index) => rel[:index].to_owned()
      None => continue
    }
    let base = rel[dir.length() + 1:].to_owned()
    let mut target = -1
    for index, group in groups {
      if group.rel == dir {
        target = index
        break
      }
    }
    if target < 0 {
      groups.push(PlanPackage::{
        rel: dir,
        pkg_text: "",
        has_program: false,
        file_names: [],
      })
      target = groups.length() - 1
    }
    let group = groups[target]
    group.file_names.push(base)
    if base == "moon.pkg" {
      group.pkg_text = content
    } else if base.has_suffix(".mbt") && content.contains("pub fn program(") {
      // 与 walk / direct_scan 同口径：只认声明 `pub fn program(`，
      // `program_signature` 这类同名前缀不算挂载点
      group.has_program = true
    }
  }
  let package_sources : Array[(String, String, Bool, Array[String])] = []
  for group in groups {
    if group.pkg_text != "" {
      package_sources.push(
        (group.rel, group.pkg_text, group.has_program, group.file_names),
      )
    }
  }
  ProjectSource::{
    root,
    module_manifest: plan_content(files, "\{root}/moon.mod"),
    package_sources,
    // 目录树交给下次真扫描（walk 读盘）补全：刚写完的树就是计划里这些路径
    dirs: [],
  }
}

///|
/// 计划里某绝对路径的内容（找不到给空串）。
fn plan_content(files : Array[(String, String)], path : String) -> String {
  for pair in files {
    if pair.0 == path {
      return pair.1
    }
  }
  ""
}
