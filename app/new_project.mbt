///|
/// 新建工程骨架（folder projects）：把「新建示例项目」落到用户选定的本地
/// 文件夹——moon.mod + 可编译的 app 包（导出 bundle 同款内核快照 + 生成源码）
/// + 设计器布局真源 form.mbt + IR 快照（重开恢复 / AI 继续编辑的事实源）。
///
/// 三个既有事实在这里汇合，不新造格式：
/// 1. 内核（domain/ir、studio_lang、codec、compiled_runtime、runner）逐字节
///    复用导出表（`@export.kernel_file_sources`）——`wzzc-dev/moui_studio`
///    未上注册表，生成的工程只能自包含；漂移由 export_test 锁定。
/// 2. 事件真源 handlers.mbt 与布局真源 form.mbt 走 `code_project_files`
///    同一条生成链；提案采纳后的 `EvCodeProjectWrite` 写同一路径同一内容。
/// 3. IR 快照存 `<root>/.studio/program.json`（`.studio/` 被工程扫描跳过，
///    与预览 harness 同目录惯例）；磁盘→IR 反解析是 workbench M6 范围，
///    快照是它落地前的恢复机制。

///|
/// IR 快照在工程内的固定路径（相对工程根）。
pub const PROGRAM_SNAPSHOT_REL : String = ".studio/program.json"

///|
/// 新建工程进行中的草稿：模板 IR + 待写文件队列（游标推进，与
/// PreviewWriteState 同款写盘节奏——逐文件 ServiceTask，回执推进游标）。
pub(all) struct NewProjectDraft {
  /// 模板下标（-1 = 空白程序）；完成步取它装载程序内存态
  template_index : Int
  /// 模板 IR（骨架文件与完成态程序的同源快照）
  program : @ir.StudioProgram
  /// 待写文件队列：绝对路径 → 内容
  files : Array[(String, String)]
  /// 已写游标
  mut done : Int
}

///|
/// 文件夹名 → 模块名：只保留字母数字折叠为连字符（与导出器同一口径，
/// MoonBit 模块名友好）。
pub fn new_project_module_name(root : String) -> String {
  let basename = match root.rev_find("/") {
    Some(index) => root[index + 1:].to_owned()
    None => root
  }
  @export.sanitize_name(basename)
}

///|
/// 新建工程的落盘文件集：路径 → 内容。`module_name` 来自文件夹名；
/// `program` 是模板 IR（决定 handlers/form/project_data 与 IR 快照）。
pub fn new_project_skeleton_files(
  root : String,
  module_name : String,
  program : @ir.StudioProgram,
) -> Array[(String, String)] {
  let json = @codec.encode_program(program)
  let files : Array[(String, String)] = []
  files.push(("\{root}/moon.mod", @export.moon_mod(module_name)))
  // 内核包清单：内容是逐字节内核快照，清单由导出器的 pkg 生成函数出
  // （模块路径指向工程本地包——`wzzc-dev/moui_studio` 未上注册表，工程
  // 必须自包含）。
  files.push(("\{root}/domain/ir/moon.pkg", @export.ir_pkg()))
  files.push(
    ("\{root}/domain/studio_lang/moon.pkg", @export.studio_lang_pkg(module_name)),
  )
  files.push(("\{root}/domain/codec/moon.pkg", @export.codec_pkg(module_name)))
  files.push(
    ("\{root}/compiled_runtime/moon.pkg", @export.compiled_runtime_pkg(module_name)),
  )
  files.push(("\{root}/app/moon.pkg", @export.app_pkg(module_name)))
  for pair in @export.kernel_file_sources() {
    files.push(("\{root}/\{pair.0}", pair.1))
  }
  files.push(
    ("\{root}/app/project_data.mbt", @export.project_data_mbt(json)),
  )
  files.push(("\{root}/app/handlers.mbt", @export.generated_handlers_mbt(json)))
  // form.mbt 不进应用骨架：render_form 产出的 `on_click=<handler 函数名>`
  // 引用编译轨函数，与 @views 的 Msg 参数类型不兼容（workbench M6 的
  // 布局真源语义未落地）——放了必编不过，不如诚实不含。
  files.push(("\{root}/\{PROGRAM_SNAPSHOT_REL}", json))
  files
}

///|
/// 工程是否为「Studio 应用骨架」布局：首个 `pub fn program` 包带 runner.mbt
/// （内核快照的标记文件）。决定提案采纳时要不要连 project_data.mbt 一起
/// 刷新——编译面里的内嵌 IR 若不跟随提案，构建产物会停在旧程序上。
pub fn is_studio_app_bundle(project : ProjectRecord) -> Bool {
  match project.scanned.program_packages {
    [first, ..] =>
      match package_files_of(project, first) {
        Some(files) => files.contains("runner.mbt")
        None => false
      }
    [] => false
  }
}

///|
fn package_files_of(
  project : ProjectRecord,
  rel : String,
) -> Array[String]? {
  for pkg in project.scanned.packages {
    if pkg.rel_path == rel {
      return Some(pkg.files)
    }
  }
  None
}

///|
/// 模板下标 → 初始程序：-1 = 空白程序，其余取内置模板库（越界回退空白）。
pub fn template_program(index : Int) -> @ir.StudioProgram {
  let samples = @proposals.all_samples()
  if index >= 0 && index < samples.length() {
    samples[index]
  } else {
    empty_program()
  }
}

///|
/// 目标目录可写性（骨架落盘前置检查）：必须是已存在的目录，且**没有
/// moon.mod**——拒绝把骨架写进已有 MoonBit 模块（防覆盖用户工程）。
/// 同步 `@x/fs` 检查：单次两个 stat，不值得起协程。
pub fn dir_is_writable(root : String) -> Result[Unit, String] {
  if !@x/fs.path_exists(root) {
    return Err("目录不存在：\{root}")
  }
  let is_dir = @x/fs.is_dir(root) catch {
    _ => false
  }
  if !is_dir {
    return Err("不是目录：\{root}")
  }
  if @x/fs.path_exists("\{root}/moon.mod") {
    return Err("目录已是 MoonBit 模块（\{root}/moon.mod 在）——换个空文件夹新建")
  }
  Ok(())
}

///|
/// 落盘前确保骨架的目录树存在：native `write_text` 不建父目录，逐文件
/// 先 mkdir（同步 @x/fs——与 import_single_source 建 .studio/preview 同款
/// 先例；约 6 个目录，UI 线程代价可忽略）。已存在时 create_dir 失败忽略。
pub fn ensure_skeleton_dirs(files : Array[(String, String)]) -> Unit {
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
/// 不含中间层（`<root>/domain` 本身不是任何文件的目录）。从**工程根**起
/// 逐级 create_dir，已存在的级别失败忽略。`dir` 必须在 `root` 之下。
pub fn ensure_dir_under(dir : String) -> Unit {
  // 全路径逐级建：绝对路径的根段已存在，create_dir 失败即忽略——
  // 等价于 mkdir -p（对已存在层级 no-op）。
  let mut prefix = ""
  for view in dir.split("/") {
    let seg = view.to_owned()
    if seg == "" {
      prefix = "/"
      continue
    }
    prefix = if prefix == "/" {
      "/" + seg
    } else {
      prefix + "/" + seg
    }
    ignore(@x/fs.create_dir(prefix) catch { _ => () })
  }
}

///|
/// 写队列推进：游标未到队尾就发下一个 write_text（回执回到
/// NewProjectFileWritten 推游标）；写完收尾——注册工程、装载模板程序。
fn write_next_project_file(
  model : Model,
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  match model.new_project {
    Some(draft) =>
      if draft.done < draft.files.length() {
        let (path, content) = draft.files[draft.done]
        (
          model,
          services
          .files()
          .write_text(path, content)
          .effect(map=r => NewProjectFileWritten(r)),
        )
      } else {
        (finish_new_project(model, services), @moui.Effect::none())
      }
    None => (model, @moui.Effect::none())
  }
}

///|
/// 新建工程完成态：合成 ProjectSource（内容与刚落盘的骨架同源，免重读）
/// 走 import_single_source 的既有管道——注册 ProjectRecord、置活跃、写
/// 预览 harness——再装载模板程序（撤销点/运行态/选中态重置同一纪律），
/// 记 program_root。骨架文件已含 IR 快照，恢复流下次激活即可用。
fn finish_new_project(
  model : Model,
  services : @services.AppServices,
) -> Model {
  match model.new_project {
    Some(draft) => {
      let root = match draft.files.get(0) {
        Some((path, _)) => dirname_of_skeleton_path(path)
        None => return { ..model, new_project: None, }
      }
      let module_name = new_project_module_name(root)
      let pkg_text = match draft.files.get(1) {
        Some((_, content)) => content
        None => ""
      }
      let source : @project.ProjectSource = {
        root,
        module_manifest: @export.moon_mod(module_name),
        package_sources: [
          ("app", pkg_text, true, [
            "runner.mbt", "project_data.mbt", "handlers.mbt",
          ]),
        ],
        dirs: [],
      }
      let (imported, _effect) = import_single_source(
        model,
        services.files(),
        source,
      )
      let loaded = load_template_program(imported, draft.template_index)
      let done = push_toast(
        loaded,
        text_with(translator(loaded), "app.project.created", [
          ("a", root),
        ]),
        false,
      )
      {
        ..done,
        program_root: root,
        new_project: None,
        new_project_confirmed: false,
      }
    }
    None => model
  }
}

///|
/// 骨架文件队列首项（moon.mod）的绝对路径 → 工程根。
fn dirname_of_skeleton_path(path : String) -> String {
  match path.rev_find("/") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
/// NewProjectRequested 服务臂：一次性放行标记 / 有未保存工作转确认 /
/// Web 无目录选择能力显式降级。放行 = 置草稿并发起目录选择。
fn new_project_requested(
  model : Model,
  index : Int,
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  let proceed = model.new_project_confirmed || !program_has_work(model)
  let pending_request = model.pending_confirm is Some(_)
  if !proceed && !pending_request {
    // 有未保存工作且未确认：转确认请求（确认续行重投本消息）
    update_pure(model, RequestConfirm(CkNewProject(index)))
  } else if proceed && model.export_available {
    let program = template_program(index)
    let draft : NewProjectDraft = {
      template_index: index,
      program,
      files: [],
      done: 0,
    }
    let options = @services.FileDialogOptions::new(
      title=text(translator(model), "app.dialog.new_project"),
    )
    (
      { ..model, new_project: Some(draft), new_project_confirmed: false, },
      services
      .files()
      .pick_directory(options~)
      .effect(map=r => NewProjectRootPicked(r)),
    )
  } else if !model.export_available {
    // Web 没有可写路径的目录选择（与导出同口径）：显式降级不假按钮
    (
      with_notice(
        model,
        text(translator(model), "app.project.new_native_only"),
        true,
      ),
      @moui.Effect::none(),
    )
  } else {
    // 确认卡已在场（先前的守卫拦截）：不再重复请求
    (model, @moui.Effect::none())
  }
}

///|
/// NewProjectRootPicked 服务臂：目录确定 → 算骨架文件集 → 建目录树 →
/// 起写盘队列。取消 = 清草稿；目录不可用（已有 moon.mod 等）= 结构化拒绝。
fn new_project_root_picked(
  model : Model,
  result : @services.ServiceTaskResult[String],
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Success(root) =>
      match model.new_project {
        Some(draft) => {
          let module_name = new_project_module_name(root)
          let files = new_project_skeleton_files(root, module_name, draft.program)
          match dir_is_writable(root) {
            Err(message) =>
              (
                with_notice({ ..model, new_project: None, }, message, true),
                @moui.Effect::none(),
              )
            Ok(_) => {
              // 守卫过了才建目录树（native write_text 不建父目录）
              ensure_skeleton_dirs(files)
              let draft = { ..draft, files, }
              write_next_project_file(
                { ..model, new_project: Some(draft) },
                services,
              )
            }
          }
        }
        None => (model, @moui.Effect::none())
      }
    Failure(error) =>
      (
        with_notice({ ..model, new_project: None, }, error.message, true),
        @moui.Effect::none(),
      )
    Cancelled => ({ ..model, new_project: None, }, @moui.Effect::none())
  }
}

///|
/// NewProjectFileWritten 服务臂：推进游标，写完收尾。失败 = 结构化通知
/// + 清草稿（半套骨架留在磁盘——moon.mod 缺失时目录仍可选回并重试）。
fn new_project_file_written(
  model : Model,
  result : @services.ServiceTaskResult[Unit],
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Success(_) =>
      match model.new_project {
        Some(draft) => {
          draft.done = draft.done + 1
          write_next_project_file(model, services)
        }
        None => (model, @moui.Effect::none())
      }
    Failure(error) =>
      (
        with_notice({ ..model, new_project: None, }, error.message, true),
        @moui.Effect::none(),
      )
    Cancelled => ({ ..model, new_project: None, }, @moui.Effect::none())
  }
}

///|
/// SetActiveProject 服务臂：纯转移照走 update_pure；目标工程与当前程序
/// 不同源时异步读 IR 快照恢复（folder projects 的「重开继续编辑」）。
/// 无快照（普通导入工程）= Failure 静默，不弹通知。
fn activate_project_with_restore(
  model : Model,
  index : Int,
  services : @services.AppServices,
) -> (Model, @moui.Effect[Msg]) {
  let (next, effect) = update_pure(model, SetActiveProject(index))
  match active_project_of(next) {
    Some(record) =>
      if record.root != next.program_root {
        (
          next,
          @moui.Effect::batch([
            effect,
            services
            .files()
            .read_text("\{record.root}/\{PROGRAM_SNAPSHOT_REL}")
            .effect(map=r => ProjectProgramLoaded(r)),
          ]),
        )
      } else {
        (next, effect)
      }
    None => (next, effect)
  }
}

///|
/// 工程程序快照回执：有快照且当前程序无未保存工作 → 载入恢复；有未保存
/// 工作 → 不打扰，引导先保存（显式降级，不静默覆盖）；坏快照 → 结构化
/// 报错；文件不存在（普通导入工程）= 常态，静默。
fn project_program_loaded(
  model : Model,
  result : @services.ServiceTaskResult[String],
) -> (Model, @moui.Effect[Msg]) {
  match result {
    Success(json) =>
      match @codec.decode_program(json) {
        Ok(program) =>
          if program_has_work(model) {
            (
              with_notice(
                model,
                text(translator(model), "app.project.snapshot_skip"),
                true,
              ),
              @moui.Effect::none(),
            )
          } else {
            let root = match active_project_of(model) {
              Some(record) => record.root
              None => ""
            }
            (load_program_state(model, program, root), @moui.Effect::none())
          }
        Err(_) =>
          (
            with_notice(
              model,
              text(translator(model), "app.project.snapshot_bad"),
              true,
            ),
            @moui.Effect::none(),
          )
      }
    Failure(_) | Cancelled => (model, @moui.Effect::none())
  }
}
