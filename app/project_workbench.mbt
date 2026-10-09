///|
/// 工程工作台(M0):导入的 MoonBit 工程。
///
/// Studio 的主编辑上下文仍是 `.studio.json` 程序(M6 才切换真源);本文件
/// 承载「导入的代码工程」——资源管理器(M0-6)与三模式预览(M1-M3)的
/// 数据对象。导入 = 选目录 → `@project.walk_project_task` 走树 → 本文件的
/// `project_record_from_source` 解析成记录,失败一路结构化报错到 toast。

///|
/// 一个导入的 MoonBit 工程(会话内,不持久化)。
pub(all) struct ProjectRecord {
  /// 工程根目录(用户选中的绝对路径)
  root : String
  /// moon.mod 的 name(如 "examples/counter")
  module_name : String
  /// 扫描结果:包清单 + 入口判定
  scanned : @project.ScannedModule
}

///|
/// 工作区根记录（资源管理器的单根行）。
///
/// `dirs` 是工作区根**自己**那一层的目录树（含非成员目录的递归展开），
/// rel_path 相对工作区根;成员目录**不**在 `dirs` 里——它们各自作为子行
/// 挂在这条根行之下（成员自己的目录树走各自 `ProjectRecord.scanned.dirs`）。
pub(all) struct WorkspaceRecord {
  root : String
  /// 根行的展示名（取根目录的最后一段）
  name : String
  dirs : Array[@project.ScannedDir]
}

///|
/// 工作区根的展示名（路径最后一段;空则退回全路径）。
pub fn workspace_display_name(root : String) -> String {
  let name = rel_path_last_segment(root)
  if name == "" {
    root
  } else {
    name
  }
}

///|
/// 资源管理器里**所有 rel 的基准目录**（绝对路径;None = 还没有可寻址的根）。
///
/// 这是全 app 唯一的「树路径 → 绝对路径」基准。口径:
///
/// - **moon.work 工作区**（`workspace_root` 有值）= 工作区根。树上的 rel 是
///   工作区相对路径（`gradlew`、`moui_studio/app/app.mbt`）——根上的文件与
///   成员目录因此同处一个命名空间,「看不到根目录下的文件」才有可能修掉。
/// - **单模块导入**（`workspace_root` 为空）= 活动工程的根。此时工作区根
///   就是工程根,rel 与工程相对路径**逐字相同**——旧行为零变化。
///
/// 为什么收成一个函数:文件读写/新建/改名/删除共十处各自拼过
/// `{project.root}/{rel}`,每处都自己 `match active_project_of(model)`。
/// 那种写法无法表达「这个 rel 属于工作区根,不属于任何工程」,根上的文件
/// 于是在每一处都落空。
pub fn tree_root_of(model : Model) -> String? {
  match model.workspace_root {
    Some(record) => Some(record.root)
    None =>
      match active_project_of(model) {
        Some(project) => Some(project.root)
        None => None
      }
  }
}

///|
/// 树上的 rel → 绝对路径（无根可寻址时 None）。
pub fn tree_abs_path(model : Model, rel : String) -> String? {
  match tree_root_of(model) {
    Some(root) => Some(join_rel(root, rel))
    None => None
  }
}

///|
/// 工程在工作区里的相对路径（工作区根到工程根）;单模块导入 = ""。
pub fn tree_rel_of_project(model : Model, project : ProjectRecord) -> String {
  match model.workspace_root {
    None => ""
    Some(record) =>
      if project.root.has_prefix(record.root + "/") {
        project.root[record.root.length() + 1:].to_owned()
      } else {
        ""
      }
  }
}

///|
/// 工程相对路径 → 工作区相对路径（在树上寻址用）。
pub fn tree_rel_of_project_file(
  model : Model,
  project : ProjectRecord,
  project_rel : String,
) -> String {
  join_rel(tree_rel_of_project(model, project), project_rel)
}

///|
/// 按根路径取工程下标（-1 = 不在册）。
pub fn project_index_of_root(model : Model, root : String) -> Int {
  let mut index = 0
  for project in model.projects {
    if project.root == root {
      return index
    }
    index = index + 1
  }
  -1
}

///|
/// 树相对路径 → 归属工程的**下标**（不属于任何成员 = None）。
///
/// 成员在树里就是工作区根下的一个子目录,所以「谁拥有这个 rel」= 它的路径
/// 是否落在某个成员目录之下（最长前缀胜出,成员路径可能是 `a/b` 多段）。
/// 单模块导入时没有成员概念,恒 None（调用方退回活动工程）。
pub fn project_index_of_tree_rel(model : Model, rel : String) -> Int? {
  match model.workspace_root {
    None => None
    Some(_) => {
      let mut best : Int? = None
      let mut best_length = -1
      let mut index = 0
      for project in model.projects {
        let member_rel = tree_rel_of_project(model, project)
        if member_rel != "" &&
          (rel == member_rel || rel.has_prefix(member_rel + "/")) &&
          member_rel.length() > best_length {
          best = Some(index)
          best_length = member_rel.length()
        }
        index = index + 1
      }
      best
    }
  }
}

///|
/// 扫描输入 → 工程记录:parse moon.mod + scan 包树。
/// 任何一步失败都是结构化 `Err(根路径:原因)`,调用方直接 with_notice。
pub fn project_record_from_source(
  source : @project.ProjectSource,
) -> Result[ProjectRecord, String] {
  match @project.parse_module_manifest(source.module_manifest) {
    Err(msg) => Err("\{source.root}:\{msg}")
    Ok(manifest) =>
      match
        @project.scan_module(manifest, source.package_sources, dirs=source.dirs) {
        Err(msg) => Err("\{source.root}:\{msg}")
        Ok(scanned) =>
          Ok(ProjectRecord::{
            root: source.root,
            module_name: manifest.name,
            scanned,
          })
      }
  }
}

///|
/// 当前选中的工程(资源管理器高亮;`active_project < 0` = 无)。
pub fn active_project_of(model : Model) -> ProjectRecord? {
  if model.active_project >= 0 && model.active_project < model.projects.length() {
    Some(model.projects[model.active_project])
  } else {
    None
  }
}

///|
/// 单模块导入(旧 ProjectWalkCompleted 单模块臂原样):upsert + 通知 +
/// 预览 harness 落盘(逐文件写 .studio/preview,回执推进游标)。
pub fn import_single_source(
  model : Model,
  files : @services.FileServices,
  source : @project.ProjectSource,
) -> (Model, @moui.Effect[Msg]) {
  match project_record_from_source(source) {
    Ok(record) => {
      // 同 root 原位替换（重复导入=刷新扫描），新工程成为当前选中
      let (projects, index) = upsert_project(model.projects, record)
      let notified = with_notice(
        { ..model, projects, active_project: index, scan_progress: None, },
        text_with(translator(model), "app.project.imported", [
          ("name", record.module_name),
        ]),
        false,
      )
      mark_projects_dirty(notified)
      // G7.4.2 修复：确保 .studio/preview/ 目录存在后再写入
      // （FileServices.write_text 不自动创建中间目录）
      let preview_dir = record.root + "/.studio/preview"
      if !@x/fs.path_exists(preview_dir) {
        try {
          @x/fs.create_dir(record.root + "/.studio")
          @x/fs.create_dir(preview_dir)
        } catch {
          _ => ()
        }
      }
      match preview_write_state_for(record) {
        None => (notified, @moui.Effect::none())
        Some(state) =>
          match preview_write_current(state) {
            None => (notified, @moui.Effect::none())
            Some((path, content)) =>
              (
                { ..notified, preview_write: Some(state), },
                files
                .write_text(path, content)
                .effect(map=r => PreviewFileWritten(r)),
              )
          }
      }
    }
    Err(msg) => (with_notice(model, msg, true), @moui.Effect::none())
  }
}

///|
/// 工作区导入(G2):逐成员建记录并 upsert(最后一个成功成员成为 active);
/// 失败成员与坏成员全部进汇总通知——绝不静默。无预览 harness
/// (workspace 成员按单模块重新导入即得,见计划 Non-goals)。
///
/// `silent` = 启动恢复路径:同样的树照建,但**不弹通知**。boot 每次都
/// 报一次「已导入 N 个模块」是噪音(用户没做任何操作),而用户主动导入时
/// 那条通知是必要的反馈。判据是「谁发起的」,不是「结果是什么」。
pub fn import_workspace_scan(
  model : Model,
  scan : @project.WorkspaceScan,
  silent? : Bool = false,
) -> (Model, @moui.Effect[Msg]) {
  let t = translator(model)
  let mut projects = model.projects
  let mut last_index = model.active_project
  let mut imported = 0
  let skipped : Array[String] = []
  for source in scan.loaded {
    match project_record_from_source(source) {
      Ok(record) => {
        let (next, index) = upsert_project(projects, record)
        projects = next
        last_index = index
        imported = imported + 1
      }
      Err(msg) => skipped.push(msg)
    }
  }
  for entry in scan.failed {
    let (path, reason) = entry
    skipped.push("\{path}:\{reason}")
  }
  if imported == 0 {
    // 全部失败:用第一条原因说话(逐条列 54 行没人读,修复指引在原因里)。
    // 启动恢复路径静默——用户没发起导入,报「导入失败」只会困惑。
    let reason = if skipped.length() > 0 { skipped[0] } else { "无成员" }
    let failed = { ..model, scan_progress: None, }
    (
      if silent {
        failed
      } else {
        with_notice(
          failed,
          text_with(t, "app.project.import_failed", [("reason", reason)]),
          true,
        )
      },
      @moui.Effect::none(),
    )
  } else {
    let message = if skipped.is_empty() {
      text_with(t, "app.project.imported_n", [("n", imported.to_string())])
    } else {
      text_with(t, "app.project.import_summary", [
        ("n", imported.to_string()),
        ("m", skipped.length().to_string()),
        ("reason", skipped[0]),
      ])
    }
    let assembled = {
      ..model,
      projects,
      active_project: last_index,
      // 工作区根记录:资源管理器的单根行。没有它,根上的
      // moon.work/README.md/gradlew 在树里没有出现的位置。
      workspace_root: Some(WorkspaceRecord::{
        root: scan.root,
        name: workspace_display_name(scan.root),
        dirs: scan.root_dirs,
      }),
      scan_progress: None,
    }
    // 启动恢复不弹通知（用户没发起导入）;主动导入才说话
    let notified = if silent {
      assembled
    } else {
      with_notice(assembled, message, false)
    }
    // 恢复路径不标脏:没改任何东西,不该触发一次存储写回
    if !silent {
      mark_projects_dirty(notified)
    }
    (notified, @moui.Effect::none())
  }
}

///|
/// 工程工作台存储格式（G2 W3）：`.studio/projects.json` 的
/// `moui.studio.projects v1`。只存 {root, module_name} + active_root——
/// 不落扫描树（数千目录的 JSON 又大又立刻陈旧），启动重扫拿新鲜树。
///
/// **另存 `workspace_root`**（可缺省）:不存它,重启后工作区根就丢了——
/// 成员会被当成互不相干的工程**平铺成顶层行**,每行显示完整 module_name
/// （`examples/counter`）,而 `examples/` 那层中间目录消失（用户实测反馈）。
/// 字段可缺省 = v1 旧文件仍能读（缺省即「没有工作区」,退回逐工程根）。
///
/// 未知版本/格式拒绝不迁移（与 ai-sessions 同纪律）。
const PROJECTS_STORE_FORMAT : String = "moui.studio.projects"

///|
const PROJECTS_STORE_VERSION : Int = 1

///|
/// 编码当前工程列表（root/module_name 摘要 + active_root + 工作区根）。
pub fn encode_project_store(model : Model) -> String {
  let items : Array[Json] = []
  for project in model.projects {
    let item = Map([])
    item["root"] = Json::string(project.root)
    item["module_name"] = Json::string(project.module_name)
    items.push(Json::object(item))
  }
  let active_root = if model.active_project >= 0 &&
    model.active_project < model.projects.length() {
    model.projects[model.active_project].root
  } else {
    ""
  }
  let root = Map([])
  root["format"] = Json::string(PROJECTS_STORE_FORMAT)
  root["version"] = Json::number(PROJECTS_STORE_VERSION.to_double())
  root["active_root"] = Json::string(active_root)
  root["projects"] = Json::array(items)
  // 工作区根:有则存,没有就**不写这个键**（旧读取方零影响）
  match model.workspace_root {
    Some(record) => root["workspace_root"] = Json::string(record.root)
    None => ()
  }
  Json::object(root).stringify()
}

///|
/// 解码存储文本 → 存储载荷（active_root + 工程列表 + 工作区根）。
///
/// 任何结构不符都结构化报错，调用方决定是否说话（boot 首跑文件不存在 =
/// Failure 静默）。
pub(all) struct ProjectStorePayload {
  active_root : String
  /// (root, module_name)
  projects : Array[(String, String)]
  /// 工作区根（无则空串 = 逐工程根渲染）
  workspace_root : String
}

///|
pub fn decode_project_store(
  text : String,
) -> Result[ProjectStorePayload, String] {
  let payload = @json.parse(text) catch {
    _ => return Err("projects.json:不是合法 JSON")
  }
  let fields = match payload {
    Object(fields) => fields
    _ => return Err("projects.json:不是 JSON 对象")
  }
  let format_ok = match fields.get("format") {
    Some(String(value)) => value == PROJECTS_STORE_FORMAT
    _ => false
  }
  if !format_ok {
    return Err("projects.json:格式标识不符")
  }
  let version_ok = match fields.get("version") {
    Some(Number(value, ..)) => value == PROJECTS_STORE_VERSION.to_double()
    _ => false
  }
  if !version_ok {
    return Err("projects.json:未知版本(拒绝迁移,请重新导入)")
  }
  let active_root = match fields.get("active_root") {
    Some(String(value)) => value
    _ => ""
  }
  let items = match fields.get("projects") {
    Some(Array(values)) => values
    _ => return Err("projects.json:缺少 projects 数组")
  }
  let records : Array[(String, String)] = []
  for item in items {
    match item {
      Object(item_fields) => {
        let root = match item_fields.get("root") {
          Some(String(value)) => value
          _ => return Err("projects.json:成员缺 root")
        }
        let name = match item_fields.get("module_name") {
          Some(String(value)) => value
          _ => return Err("projects.json:成员缺 module_name")
        }
        records.push((root, name))
      }
      _ => return Err("projects.json:成员不是对象")
    }
  }
  // 工作区根:可缺省（旧文件 / 单模块导入都没有这个键）
  let workspace_root = match fields.get("workspace_root") {
    Some(String(value)) => value
    _ => ""
  }
  Ok(ProjectStorePayload::{ active_root, projects: records, workspace_root, })
}

///|
/// 工程列表结构性变化的统一出口（ai-sessions 同款）：进 outbox 事件,
/// 由总线翻译成写盘请求（未配置存储路径的组合根不注册监听器 → 零开销）。
pub fn mark_projects_dirty(model : Model) -> Unit {
  model.outbox.push(EvProjectsDirty)
}

///|
/// boot 恢复收尾：全部重扫回来后按存储的 active_root 落位选中（找不到
/// 就 -1 = 无），并清掉临时恢复态。
pub fn finish_restore_active(model : Model) -> Model {
  let mut index = -1
  let mut i = 0
  for project in model.projects {
    if project.root == model.restore_active_root {
      index = i
    }
    i = i + 1
  }
  { ..model, active_project: index, restore_active_root: "", }
}

///|
/// 把导入的工程并入列表:同 root 已存在则**原位替换**(重复导入刷新扫描),
/// 否则插到表头;返回 (新列表, 该工程的新下标)。
pub fn upsert_project(
  projects : Array[ProjectRecord],
  record : ProjectRecord,
) -> (Array[ProjectRecord], Int) {
  let mut existing = -1
  let mut i = 0
  for project in projects {
    if project.root == record.root {
      existing = i
    }
    i = i + 1
  }
  let updated : Array[ProjectRecord] = []
  if existing < 0 {
    updated.push(record)
    for project in projects {
      updated.push(project)
    }
    (updated, 0)
  } else {
    let mut index = 0
    for project in projects {
      if index == existing {
        updated.push(record)
      } else {
        updated.push(project)
      }
      index = index + 1
    }
    (updated, existing)
  }
}

///|
/// 待执行构建(纯数据;执行闭包在程序包装层注入,与 CompileSubmit 同位)。
pub(all) struct ProjectBuildRequest {
  kind : @build.BuildKind
  root : String
  entry_rel : String
}

///|
/// 构建提交签名与预览 web 控制束的类型定义已收编进内核服务注册表
/// （`kernel/services.mbt`，M1 插件化）；这里保留公开别名，既有引用零改动
/// （`PreviewWebControls` 在内核泛型于消息类型，app 侧固化为本包 Msg）。
pub type BuildSubmit = @kernel.BuildSubmit

///|
pub type PreviewWebControls = @kernel.PreviewWebControls[Msg]

///|
/// 当前工程对应 kind 的入口包(缺 = ""):
/// FramePreview 用生成的预览 harness 包(M1 落地),
/// WebPreview / RunNative 用扫描出的 web / native 入口。
pub fn build_entry_rel(
  kind : @build.BuildKind,
  project : ProjectRecord,
) -> String {
  match kind {
    BkFramePreview => ".studio/preview"
    BkWebPreview => project.scanned.web_entry
    BkRunNative => project.scanned.native_entry
  }
}

///|
/// 预览 harness 落盘状态:待写文件队列(绝对路径, 内容)+ 已写游标。
pub(all) struct PreviewWriteState {
  files : Array[(String, String)]
  done : Int
}

///|
/// 为导入成功的工程构造预览落盘任务:工程含 `pub fn program` 包才生成
/// (无逻辑入口的工程没有可预览的东西,诚实跳过)。
pub fn preview_write_state_for(project : ProjectRecord) -> PreviewWriteState? {
  match project.scanned.program_packages {
    [first, ..] => {
      let files = @project.preview_harness_files(project.module_name, first)
      let queued : Array[(String, String)] = []
      for file in files {
        queued.push(
          (
            project.root + "/" + @project.PREVIEW_PACKAGE_REL + "/" + file.0,
            file.1,
          ),
        )
      }
      Some(PreviewWriteState::{ files: queued, done: 0, })
    }
    [] => None
  }
}

///|
/// 预览 harness 的待写文件(结构体 spread 共享数组,按索引取,不取出改)。
pub fn preview_write_current(state : PreviewWriteState) -> (String, String)? {
  if state.done >= 0 && state.done < state.files.length() {
    Some(state.files[state.done])
  } else {
    None
  }
}

///|
/// 预览 web 控制束的类型定义与 noop 已收编进内核
/// （`kernel/services.mbt` 的 `PreviewWebControls[Msg]`，M1 插件化）；
/// app 侧别名见本文件顶部。

///|
/// active tab（G4 多标签;下标越界 = None）。
pub fn active_project_file(model : Model) -> OpenProjectFile? {
  if model.open_file_index >= 0 &&
    model.open_file_index < model.open_project_files.length() {
    Some(model.open_project_files[model.open_file_index])
  } else {
    None
  }
}

///|
/// tab 脏标记：草稿偏离落盘基准。
pub fn file_is_dirty(open : OpenProjectFile) -> Bool {
  open.draft != open.saved_content
}

///|
/// `.md` tab 的会话字段构造：md 文件建/换源重建 MoMark 文档会话,
/// 其余文件恒 None。所有 `OpenProjectFile::{..}` 构造点统一走它,
/// 避免 `md_session` 在各处手写后缀判断。
pub fn with_md_session(
  rel~ : String,
  content~ : String,
) -> @moui_richtext.MarkdownDocumentSession? {
  if rel.has_suffix(".md") {
    Some(@moui_richtext.MarkdownDocumentSession::new(content))
  } else {
    None
  }
}

///|
/// 任一 tab 脏（「保存全部」chip 的出现条件）。
pub fn any_file_dirty(model : Model) -> Bool {
  for file in model.open_project_files {
    if file_is_dirty(file) {
      return true
    }
  }
  false
}

///|
/// 打开文件 upsert:同 rel 原位替换（重新读取=刷新内容）,否则追加并激活。
pub fn upsert_open_file(
  files : Array[OpenProjectFile],
  open : OpenProjectFile,
) -> (Array[OpenProjectFile], Int) {
  let mut existing = -1
  let mut i = 0
  for file in files {
    if file.rel == open.rel {
      existing = i
    }
    i = i + 1
  }
  let next : Array[OpenProjectFile] = []
  for j, file in files {
    if j == existing {
      next.push(open)
    } else {
      next.push(file)
    }
  }
  if existing >= 0 {
    (next, existing)
  } else {
    next.push(open)
    (next, files.length())
  }
}

///|
/// 按 rel 找 tab 下标（无则 None）。
pub fn open_file_index_of(files : Array[OpenProjectFile], rel : String) -> Int? {
  let mut found : Int? = None
  for i, file in files {
    if file.rel == rel {
      found = Some(i)
    }
  }
  found
}

///|
/// 关闭下标处的 tab,并把 active 收敛到合法范围（删的是 active 时停在
/// 同位置的下一个 tab,尾部则回退一格）。
pub fn close_open_file_at(model : Model, index : Int) -> Model {
  if index < 0 || index >= model.open_project_files.length() {
    return model
  }
  let files : Array[OpenProjectFile] = []
  for i, file in model.open_project_files {
    if i != index {
      files.push(file)
    }
  }
  let next_index = if files.is_empty() {
    -1
  } else if index < files.length() {
    index
  } else {
    files.length() - 1
  }
  { ..model, open_project_files: files, open_file_index: next_index, }
}

///|
/// 原位替换下标处的 tab（光标/草稿/脏基准回写）。
pub fn replace_open_file_at(
  files : Array[OpenProjectFile],
  index : Int,
  open : OpenProjectFile,
) -> Array[OpenProjectFile] {
  let next : Array[OpenProjectFile] = []
  for i, file in files {
    if i == index {
      next.push(open)
    } else {
      next.push(file)
    }
  }
  next
}

///|
/// 新文件 rel 校验（G4 CRUD）：非空、不以 `/` 开头（工程内相对路径）、
/// 不含 `..`（不逃逸工程根）。空格等其余字符交给文件系统裁决。
pub fn valid_new_file_rel(rel : String) -> Bool {
  rel != "" && !rel.has_prefix("/") && !rel.contains("..")
}

///|
/// 改名后同步 open tabs:rel 替换,内容与光标状态原样保留。
pub fn rename_open_file(
  files : Array[OpenProjectFile],
  old : String,
  new : String,
) -> Array[OpenProjectFile] {
  let next : Array[OpenProjectFile] = []
  for file in files {
    if file.rel == old {
      next.push({ ..file, rel: new, })
    } else {
      next.push(file)
    }
  }
  next
}

///|
/// 工程文件树里是否已有该目录 rel（新建文件夹重名拒绝的依据）。
///
/// 查的是 `scanned.dirs`（完整目录树）而不是 `packages`——后者只含带
/// `moon.pkg` 的目录，用它判重会把「已存在一个非包目录」误判成可建，
/// 于是 `create_dir` 静默失败或覆盖语义不明。
pub fn project_has_dir(model : Model, rel : String) -> Bool {
  match active_project_of(model) {
    None => false
    Some(project) => {
      let mut found = false
      for dir in project.scanned.dirs {
        if dir.rel_path == rel {
          found = true
        }
      }
      found
    }
  }
}

///|
/// 工程文件树里是否已有该 rel（新建重名拒绝的依据）。
pub fn project_has_file(model : Model, rel : String) -> Bool {
  match active_project_of(model) {
    None => false
    Some(project) => {
      let mut found = false
      for pkg in project.scanned.packages {
        for name in pkg.files {
          let file_rel = if pkg.rel_path == "" {
            name
          } else {
            "\{pkg.rel_path}/\{name}"
          }
          if file_rel == rel {
            found = true
          }
        }
      }
      found
    }
  }
}

///|
/// 保存后的 live 诊断（G4 F4）：保存的 .mbt 且编译轨可用、构建空闲、
/// 工程有 web 入口时，发一次 web 构建事件（诊断汇 Problems 的既有链）。
/// 条件不满足全部静默——诊断是顺手送的,不该变成打扰。
pub fn auto_build_after_save(
  model : Model,
  rel : String,
) -> (Model, @moui.Effect[Msg]) {
  if !rel.has_suffix(".mbt") ||
    !model.compile_track_available ||
    model.build_busy {
    return (model, @moui.Effect::none())
  }
  match active_project_of(model) {
    None => (model, @moui.Effect::none())
    Some(project) => {
      let entry_rel = build_entry_rel(BkWebPreview, project)
      if entry_rel == "" {
        (model, @moui.Effect::none())
      } else {
        // 过门即发构建事件（M1 事件化同款）:busy 置位防重复排队
        model.outbox.push(EvBuildSubmit(BkWebPreview, project.root, entry_rel))
        ({ ..model, build_busy: true, }, @moui.Effect::none())
      }
    }
  }
}

///|
/// 插件管理（G7.3）：禁用判定。静态装配的诚实口径——禁用 = 贡献项入口
/// 被过滤（Feature 状态保留），不是运行时卸载；「安装新插件需重新构建」。
pub fn plugin_active(model : Model, id : String) -> Bool {
  !model.plugin_disabled.contains(id)
}

///|
/// 插件存储编码（settings 值是字符串）:逗号连接的禁用 id 列表。
pub fn encode_plugin_disabled(model : Model) -> String {
  let buf = StringBuilder()
  let mut first = true
  for id in model.plugin_disabled {
    if !first {
      buf.write_string(",")
    }
    buf.write_string(id)
    first = false
  }
  buf.to_string()
}

///|
/// 解析存储的禁用清单（空串 = 全部启用;未知 id 忽略）。
pub fn decode_plugin_disabled(text : String) -> Array[String] {
  let ids : Array[String] = []
  if text == "" {
    return ids
  }
  for piece in text.split(",") {
    let id = piece.to_owned()
    if id == "ai" || id == "terminal" || id == "markdown" {
      ids.push(id)
    }
  }
  ids
}
