///|
/// 骨架落盘前的目录准备：可写性守卫 + 父目录树。同步 `@x/fs`——检查是
/// 单次 stat，建目录是约 6 个 mkdir，不值得起协程（与 import_single_source
/// 建 `.studio/preview` 同款先例）。

///|
/// 目标目录可写性：必须是已存在的目录，且**没有 moon.mod**——拒绝把骨架
/// 写进已有 MoonBit 模块（防覆盖用户工程）。
pub fn dir_is_writable(root : String) -> Result[Unit, String] {
  if !@x/fs.path_exists(root) {
    return Err("目录不存在：\{root}")
  }
  let is_dir = @x/fs.is_dir(root) catch { _ => false }
  if !is_dir {
    return Err("不是目录：\{root}")
  }
  if @x/fs.path_exists("\{root}/moon.mod") {
    return Err(
      "目录已是 MoonBit 模块（\{root}/moon.mod 在）——换个空文件夹新建",
    )
  }
  Ok(())
}

///|
/// 落盘前确保骨架的目录树存在：native `write_text` 不建父目录，逐文件
/// 先 mkdir（同一目录只建一次）。
pub fn ensure_parent_dirs(files : Array[(String, String)]) -> Unit {
  let seen : Array[String] = []
  for pair in files {
    let (path, _) = pair
    let dir = match path.rev_find("/") {
      Some(index) => path[:index].to_owned()
      None => continue
    }
    let mut known = false
    for existing in seen {
      if existing == dir {
        known = true
        break
      }
    }
    if !known {
      seen.push(dir)
      ignore(ensure_dir_under(dir))
    }
  }
}

///|
/// mkdir -p 语义的最小实现：`@x/fs.create_dir` 只建单级，而骨架目录列表
/// 不含中间层（`<root>/domain` 本身不是任何文件的目录）。从根起逐级建，
/// 已存在的级别失败忽略。
fn ensure_dir_under(dir : String) -> Unit {
  // 全路径逐级建：绝对路径的根段已存在，create_dir 失败即忽略——
  // 等价于 mkdir -p（对已存在层级 no-op）。
  let mut prefix = ""
  for view in dir.split("/") {
    let seg = view.to_owned()
    if seg == "" {
      prefix = "/"
      continue
    }
    prefix = if prefix == "/" { "/" + seg } else { prefix + "/" + seg }
    ignore(@x/fs.create_dir(prefix) catch { _ => () })
  }
}
