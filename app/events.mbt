///|
/// Studio 跨域事件（M1 插件化）：取代「update 置位 flag → 包装层 diff 消费」
/// 的三个跨域标记（`pending_code_project`/`pending_build`/`build_seq`）。
///
/// 纪律（与 kernel 事件总线同源）：
/// 1. 事件在**事实发生处**发出，载荷显式携带消费方需要的全部数据——消费方
///    （组合根监听器）不回查模型；
/// 2. 事件进 `model.outbox`，程序包装层每趟**排空一次**并经总线翻译成消息；
/// 3. 事件发完即忘：不回读、不计数（顺序由 outbox 数组保持）。
pub(all) enum StudioEvent {
  /// 代码工程骨架待落盘（SelectTemplate → load_template_program / 提案采纳 /
  /// .studio.json 迁移器三条路的汇合点）。载荷 = 目标目录 + form.mbt +
  /// handlers.mbt 全文（解析在发出点完成，见 `emit_code_project_write`）+
  /// 内嵌 IR 的 project_data.mbt 全文（**仅 Studio 应用骨架布局**——编译面
  /// 里的内嵌 IR 不跟随提案，构建产物会停在旧程序上；"" = 布局不含，跳过）。
  EvCodeProjectWrite(String, String, String, String)
  /// 程序 IR 快照待落盘：载荷 = `<root>/.studio/program.json` 绝对路径 +
  /// 编码 IR。重开恢复 / AI 继续编辑的事实源（磁盘→IR 反解析是 workbench
  /// M6 范围，快照是它落地前的恢复机制）。
  EvProgramSnapshotWrite(String, String)
  /// 构建请求已过门（工具链可达 + busy 互斥 + 工程在册 + 入口在册）。
  /// 载荷 = kind + 工程根 + 入口包相对路径。
  EvBuildSubmit(@build.BuildKind, String, String)
  /// Web 预览重建完成且 URL 变化（含首次）→ webview 导航。
  EvPreviewWebNavigate(String)
  /// Web 预览重建完成且 URL 未变 → webview 刷新。
  EvPreviewWebReload
  /// 提案被采纳（M3）：语义事实的扩展点——落盘事实由 EvCodeProjectWrite
  /// 承载，本事件供未来插件订阅（当前无消费者 → 排空时零开销 NoEffect）。
  EvProposalAccepted(Int, String)
  /// AI 会话发生结构性变化（M5）：提交/采纳/拒绝/新建/切换/删除/置顶/
  /// 改名/流式完成。组合根配置了存储路径时由总线翻译成写盘请求。
  EvAiSessionsDirty
  /// 工程列表发生结构性变化（G2）：导入/移除/删除文件重扫。
  /// 组合根配置了存储路径时由总线翻译成写盘请求。
  EvProjectsDirty
}

///|
/// 代码工程写盘事件的统一发出点：目录优先取 `pending_open_dir`（迁移器：
/// 旧 .studio.json 所在目录，消费即清位），否则打开工程的首个程序包；
/// 两者皆无时静默不发（与原包装层「静默清位」同语义——首次体验不弹写盘噪音）。
/// `code_project_files` 从当前 IR 快照派生双腿（form.mbt / handlers.mbt），
/// 与导出 bundle 同源。
pub fn emit_code_project_write(model : Model) -> Model {
  let (dir_override, model) = match model.pending_open_dir {
    Some(dir) => (Some(dir), { ..model, pending_open_dir: None, })
    None => (None, model)
  }
  match dir_override {
    Some(dir) => emit_code_project_write_to(model, dir)
    None =>
      match active_project_of(model) {
        Some(project) =>
          match code_project_target(project) {
            Some(pkg) =>
              emit_code_project_write_to(model, "\{project.root}/\{pkg}")
            None => model
          }
        None => model
      }
  }
}

///|
fn emit_code_project_write_to(model : Model, dir : String) -> Model {
  let files = code_project_files(model.program)
  // Studio 应用骨架布局（首程序包带 runner.mbt）：编译面里的内嵌 IR
  // 必须跟随提案刷新，而 form.mbt 不参与该布局（见 new_project.mbt）——
  // form 载荷置空 = 组合根跳过；普通导入工程相反：写 form/handlers，
  // 不塞 project_data。
  let (form_mbt, project_data) = match active_project_of(model) {
    Some(project) =>
      if is_studio_app_bundle(project) {
        ("", @export.project_data_mbt(@codec.encode_program(model.program)))
      } else {
        (files.form_mbt, "")
      }
    None => (files.form_mbt, "")
  }
  model
  .outbox
  .push(EvCodeProjectWrite(dir, form_mbt, files.handlers_mbt, project_data))
  model
}

///|
/// IR 快照写盘事件的统一发出点：目标 = 程序所属工程根的
/// `.studio/program.json`；无所属工程（出厂样例未恢复、独立 .studio.json）
/// 静默不发——没有工程根就没有「下次打开」的落点。
pub fn emit_program_snapshot(model : Model) -> Model {
  let root = if model.program_root != "" {
    Some(model.program_root)
  } else {
    match active_project_of(model) {
      Some(record) => Some(record.root)
      None => None
    }
  }
  match root {
    Some(root) => {
      model
      .outbox
      .push(
        EvProgramSnapshotWrite(
          "\{root}/\{PROGRAM_SNAPSHOT_REL}",
          @codec.encode_program(model.program),
        ),
      )
      model
    }
    None => model
  }
}
