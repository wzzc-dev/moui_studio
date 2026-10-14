///|
/// 直接扫描（G7.2 性能修复）：不走 ServiceTask 回调链（每个目录一次
/// effect 派发 = 大项目 UI 冻结），改为同步 @x/fs I/O 一次函数调用
/// 完成整棵树。app 层直接在 dispatch 回调里调用（同步、无 raise）。
///
/// 与 walk_root_task 逻辑一致（同一 BFS + 跳过规则 + 上限 + 结构化报错），
/// 但用直接 I/O 替代 ServiceTask。

///|
/// 跳过目录清单（与 walk.mbt 同一规则）。
fn ds_skip_dir(name : String) -> Bool {
  match name {
    ".git"
    | ".mooncakes"
    | "_build"
    | "target"
    | "node_modules"
    | "artifacts"
    | ".studio"
    | ".vscode"
    | ".github" => true
    _ => false
  }
}

///|
/// 列目录条目：返回 (name, is_dir) 对；IO 错误返回空（该目录跳过）。
fn ds_list_dir(path : String) -> Array[(String, Bool)] {
  let result : Array[(String, Bool)] = []
  try {
    for name in @x/fs.read_dir(path) {
      if name.has_prefix(".") {
        continue
      }
      let is_dir = @x/fs.is_dir(path + "/" + name) catch { _ => false }
      result.push((name, is_dir))
    }
  } catch {
    _ => ()
  }
  result
}

///|
/// 读文本（不存在或不可读返回空串——扫描韧性口径）。
fn ds_read_text(path : String) -> String {
  @x/fs.read_file_to_string(path) catch {
    _ => ""
  }
}

///|
const DS_WALK_MAX_DIRS : Int = 2000

///|
const DS_WALK_MAX_FILES_PER_PACKAGE : Int = 200

///|
const DS_SCAN_MAX_MEMBERS : Int = 200

///|
const DS_PROGRESS_EVERY : Int = 64

///|
/// 直接扫描入口（G7.2 性能修复）。同步、不 raise——所有 IO 错误内部
/// 消化（读不了的目录跳过，moon.mod 缺失 = 结构化 Err）。
pub fn direct_scan(
  root : String,
  on_progress? : (@project.WalkProgress) -> Unit,
) -> Result[@project.ProjectScanOutput, String] {
  let progress = match on_progress {
    Some(cb) => cb
    None => fn(_) {  }
  }
  let entries = ds_list_dir(root)
  let names : Array[String] = []
  let subdirs : Array[String] = []
  for pair in entries {
    let (name, is_dir) = pair
    if is_dir {
      if !ds_skip_dir(name) {
        subdirs.push(name)
      }
    } else {
      names.push(name)
    }
  }
  if names.contains("moon.work") {
    ds_scan_workspace(root, subdirs, progress)
  } else if names.contains("moon.mod") {
    Ok(@project.ProjectScanOutput::Single(ds_scan_module(root, "", progress)))
  } else {
    Err("\{root}:目录里没有 moon.mod(不是 MoonBit 模块工程?)")
  }
}

///|
/// 扫描**工作区根自己**那一层（不含各成员内部）。
///
/// 只走一层:根上的普通文件（`moon.work`/`README.md`/`gradlew`…）与根上的
/// 非成员目录都属于这一层;成员目录自己的内容由各自的 `ds_scan_module`
/// 负责,这里不重复走（否则大工作区要扫两遍）。
///
/// 非成员目录（如 `docs/`、`scripts/`）要**递归**展开——它们不在 moon.work
/// 里,却是工作区根的可见内容,只给一个空目录行等于还是看不到东西。
fn ds_scan_workspace_root(
  root : String,
  member_rels : Array[String],
  progress : (@project.WalkProgress) -> Unit,
) -> Array[@project.ScannedDir] {
  let dirs : Array[@project.ScannedDir] = []
  let entries = ds_list_dir(root)
  let root_files : Array[String] = []
  let subdirs : Array[String] = []
  for pair in entries {
    let (name, is_dir) = pair
    if is_dir {
      if !ds_skip_dir(name) {
        subdirs.push(name)
      }
    } else {
      root_files.push(name)
    }
  }
  dirs.push(@project.ScannedDir::{ rel_path: "", files: root_files, })
  // 非成员目录递归展开（成员目录留给各自的模块扫描）
  let mut total = 0
  for name in subdirs {
    if member_rels.contains(name) {
      continue
    }
    ds_walk_root_dir(root, name, dirs, progress, total~)
    total = total + 1
  }
  dirs
}

///|
/// 递归展开工作区根下的一个非成员目录（BFS，父先于子）。
fn ds_walk_root_dir(
  root : String,
  rel : String,
  dirs : Array[@project.ScannedDir],
  progress : (@project.WalkProgress) -> Unit,
  total~ : Int,
) -> Unit {
  let queue : Array[String] = [rel]
  let mut idx = 0
  while idx < queue.length() && idx < DS_WALK_MAX_DIRS {
    let current = queue[idx]
    idx = idx + 1
    progress(@project.WalkProgress::{ scanned_dirs: total + idx, current, })
    let files : Array[String] = []
    for pair in ds_list_dir("\{root}/\{current}") {
      let (name, is_dir) = pair
      if is_dir {
        if !ds_skip_dir(name) {
          queue.push("\{current}/\{name}")
        }
      } else {
        files.push(name)
      }
    }
    dirs.push(@project.ScannedDir::{ rel_path: current, files, })
  }
}

///|
/// 扫描单个 MoonBit 模块。
fn ds_scan_module(
  root : String,
  member_rel : String,
  progress : (@project.WalkProgress) -> Unit,
) -> @project.ProjectSource {
  let abs = if member_rel == "" { root } else { "\{root}/\{member_rel}" }
  let entries = ds_list_dir(abs)
  let dir_queue : Array[String] = []
  let file_lists : Map[String, Array[String]] = Map([])
  let pkg_queue : Array[String] = []
  let mut total = 0
  let root_files : Array[String] = []
  for pair in entries {
    let (name, is_dir) = pair
    if is_dir {
      dir_queue.push(name)
    } else {
      root_files.push(name)
    }
  }
  file_lists[""] = root_files
  if root_files.contains("moon.pkg") {
    pkg_queue.push("")
  }
  let mut idx = 0
  while idx < dir_queue.length() && total < DS_WALK_MAX_DIRS {
    let rel = dir_queue[idx]
    idx = idx + 1
    total = total + 1
    if total % DS_PROGRESS_EVERY == 0 {
      let current = if member_rel == "" { rel } else { "\{member_rel}/\{rel}" }
      progress(@project.WalkProgress::{ scanned_dirs: total, current, })
    }
    let child_files : Array[String] = []
    for pair in ds_list_dir("\{abs}/\{rel}") {
      let (name, is_dir) = pair
      if is_dir {
        if !ds_skip_dir(name) {
          dir_queue.push("\{rel}/\{name}")
        }
      } else {
        child_files.push(name)
      }
    }
    file_lists[rel] = child_files
    if child_files.contains("moon.pkg") {
      pkg_queue.push(rel)
    }
  }
  let mod_text = ds_read_text("\{abs}/moon.mod")
  let results : Array[(String, String, Bool, Array[String])] = []
  let dir_entries : Array[@project.ScannedDir] = []
  for pair in file_lists {
    let (rel, files) = pair
    dir_entries.push(@project.ScannedDir::{ rel_path: rel, files, })
  }
  for pkg_rel in pkg_queue {
    let pkg_text = ds_read_text("\{abs}/\{pkg_rel}/moon.pkg")
    let files = file_lists.get(pkg_rel).unwrap_or([])
    let sources : Array[String] = []
    let mut has_program = false
    for name in files {
      if name.has_suffix(".mbt") &&
        sources.length() < DS_WALK_MAX_FILES_PER_PACKAGE {
        sources.push(name)
      }
    }

    for name in sources {
      let source = ds_read_text("\{abs}/\{pkg_rel}/\{name}")
      // 与 walk 同口径：只认声明 `pub fn program(`，排除
      // `pub fn program_signature(...)` 这类内核函数名
      if source.contains("pub fn program(") {
        has_program = true
      }
    }
    results.push((pkg_rel, pkg_text, has_program, files))
  }
  @project.ProjectSource::{
    root: abs,
    module_manifest: mod_text,
    package_sources: results,
    dirs: dir_entries,
  }
}

///|
/// 扫描 moon.work 工作区。
fn ds_scan_workspace(
  root : String,
  _root_subdirs : Array[String],
  progress : (@project.WalkProgress) -> Unit,
) -> Result[@project.ProjectScanOutput, String] {
  let work_text = ds_read_text("\{root}/moon.work")
  let members = match @project.parse_moon_work(work_text) {
    Ok(members) => members
    Err(message) => return Err("\{root}:\{message}")
  }
  if members.is_empty() {
    return Err("\{root}:moon.work 没有可导入的成员")
  }
  if members.length() > DS_SCAN_MAX_MEMBERS {
    return Err(
      "\{root}:工作区成员数超过 \{DS_SCAN_MAX_MEMBERS},放弃扫描",
    )
  }
  let loaded : Array[@project.ProjectSource] = []
  let failed : Array[(String, String)] = []
  for file_member in members {
    progress(@project.WalkProgress::{ scanned_dirs: 0, current: file_member, })
    loaded.push(ds_scan_module(root, file_member, progress))
  }
  Ok(
    @project.ProjectScanOutput::Workspace(@project.WorkspaceScan::{
      root,
      loaded,
      failed,
      // 工作区根自己那一层:根文件 + 非成员目录（成员目录内部不在这里）
      root_dirs: ds_scan_workspace_root(root, members, progress),
    }),
  )
}
