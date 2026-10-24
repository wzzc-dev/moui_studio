///|
/// 资源管理器(M0-6a)的渲染冒烟:导入工程后切到「工程」页,真实布局下
/// 模块名/包名/文件名必须可见——左栏装配(标题/搜索框条件/图标栏)任何
/// 一处接错,这里都会以「文本不见」暴露。

///|
/// 与 shell_layout_wbtest 同款:纯转移 + headless 出帧。
fn explorer_apply(model : Model, msg : Msg) -> Model {
  let (next, _) = update_pure(model, msg)
  next
}

///|
fn explorer_draw(
  model : Model,
  width : Double,
  height : Double,
) -> Array[@core.DrawCommand] {
  let program : @core.Program[Model, Msg] = @moui.Program::new_with_environment(
    init=() => (model, @moui.Effect::none()),
    update=(current, msg) => update_pure(current, msg),
    view=(current, env) => view_with_viewport(current, env.viewport_size()),
  )
  @runtime.new_program_with_dimensions(program~, width~, height~).draw_commands()
}

///|
/// 展开全部根行:本文件里「树内容可见」的渲染断言都以展开态为前提,
/// 「导入默认折叠」由专门的回归用例锁定,不在这里重复默认值。
fn explorer_tree_expanded(model : Model) -> Model {
  {
    ..model,
    project_state: { ..model.project_state, project_tree_collapsed: [], },
  }
}

///|
/// counter 形工程扫描输入(黑盒测试文件里的同构 fixture 在白盒不可见,自留一份)。
fn explorer_source() -> @project.ProjectSource {
  let mod_text =
    #|name = "examples/counter"
    #|version = "0.1.0"
    #|preferred_target = "native"
  let app_pkg =
    #|import {
    #|  "wzzc-dev/moui/views",
    #|  "wzzc-dev/moui",
    #|}
  let entry_pkg =
    #|import {
    #|  "wzzc-dev/moui",
    #|}
  @project.ProjectSource::{
    root: "/root",
    module_manifest: mod_text,
    package_sources: [
      ("app", app_pkg, true, ["moon.pkg", "app.mbt"]),
      ("web_wasm", entry_pkg, false, ["moon.pkg", "main.mbt"]),
      ("macos_skia", entry_pkg, false, ["moon.pkg", "main.mbt"]),
    ],
    dirs: [
      @project.ScannedDir::{ rel_path: "", files: ["moon.mod", "README.md"], },
      @project.ScannedDir::{ rel_path: "app", files: ["moon.pkg", "app.mbt"], },
      @project.ScannedDir::{ rel_path: "docs", files: ["guide.md"], },
      @project.ScannedDir::{
        rel_path: "web_wasm",
        files: ["moon.pkg", "main.mbt"],
      },
      @project.ScannedDir::{
        rel_path: "macos_skia",
        files: ["moon.pkg", "main.mbt"],
      },
    ],
  }
}

///|
test "explorer 渲染导入工程的模块名/包名/文件名" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  let texts = shell_texts(explorer_draw(opened, 1280.0, 800.0))
  let mut seen_module = false
  let mut seen_app_pkg = false
  let mut seen_app_file = false
  for run in texts {
    if run.text.contains("examples/counter") {
      seen_module = true
    }
    if run.text == "app" {
      seen_app_pkg = true
    }
    if run.text == "app.mbt" {
      seen_app_file = true
    }
  }
  assert_true(seen_module, msg="模块名应可见")
  assert_true(seen_app_pkg, msg="包名应可见")
  assert_true(seen_app_file, msg="文件名应可见")
}

///|
/// VS Code 口径:根目录下的普通文件(README/moon.mod 等)与**非包目录**
/// (docs/)都直接出现在树上,不需要把文件挪进包里。
test "explorer 根文件与非包目录可见" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  let texts = shell_texts(explorer_draw(opened, 1280.0, 800.0))
  let mut seen_readme = false
  let mut seen_moon_mod = false
  let mut seen_docs = false
  let mut seen_guide = false
  for run in texts {
    if run.text == "README.md" {
      seen_readme = true
    }
    if run.text == "moon.mod" {
      seen_moon_mod = true
    }
    if run.text == "docs" {
      seen_docs = true
    }
    if run.text == "guide.md" {
      seen_guide = true
    }
  }
  assert_true(seen_readme, msg="根目录 README.md 应可见")
  assert_true(seen_moon_mod, msg="根目录 moon.mod 应可见")
  assert_true(seen_docs, msg="非包目录 docs 应可见")
  assert_true(seen_guide, msg="docs 下的文件应可见")
}

///|
test "explorer 空态给导入入口" {
  let opened = explorer_apply(initial_model(), SetLeftView(LeftProject))
  let texts = shell_texts(explorer_draw(opened, 1280.0, 800.0))
  let mut seen_import = false
  for run in texts {
    if run.text.contains("导入 MoonBit 工程") {
      seen_import = true
    }
  }
  assert_true(seen_import, msg="空态应有导入入口")
}

///|
/// VS Code 资源管理器壳:标题是「资源管理器」,四个分区头同屏可见,
/// 工具栏的四个图标动作各有状态栏提示（图标按钮没有文字,提示是唯一的
/// 可发现性来源）。
///
/// 旧实现的面板标题是「工程」、没有分区、没有工具栏——这三样任何一处
/// 接错都会在这里以「文本不见」暴露。
test "explorer 壳:标题/顶级文件夹/大纲时间线/工具栏提示" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(imported, SetLeftView(LeftProject))
  let texts = shell_texts(explorer_draw(opened, 1280.0, 800.0))
  let mut seen_title = false
  let mut seen_editors = false
  let mut seen_folders_header = false
  let mut seen_outline = false
  let mut seen_timeline = false
  let mut seen_root = false
  for run in texts {
    if run.text == "资源管理器" {
      seen_title = true
    }
    if run.text == "打开的编辑器" {
      seen_editors = true
    }
    if run.text == "文件夹" {
      seen_folders_header = true
    }
    if run.text == "大纲" {
      seen_outline = true
    }
    if run.text == "时间线" {
      seen_timeline = true
    }
    // 顶层文件夹行（模块名）应可见
    if run.text.contains("examples/counter") {
      seen_root = true
    }
  }
  assert_true(seen_title, msg="面板标题应为「资源管理器」")
  assert_true(seen_root, msg="工程根应直接铺在工具栏之下")
  assert_true(seen_outline, msg="应有「大纲」分区")
  assert_true(seen_timeline, msg="应有「时间线」分区")
  // **与截图对齐的两处**:没有打开 tab 时不画「打开的编辑器」;顶层文件夹
  // 之上不套「文件夹」分区头。两处都白吃掉 24pt 纵向空间。
  assert_false(
    seen_editors,
    msg="没有打开的文件时不应画「打开的编辑器」分区",
  )
  assert_false(
    seen_folders_header,
    msg="顶层文件夹之上不应套「文件夹」分区头",
  )
}

///|
/// 「打开的编辑器」在**真的有 tab 时**才出现（与上一条构成一对）。
test "explorer 打开的编辑器分区:有 tab 才出现" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(imported, SetLeftView(LeftProject))
  let selected = explorer_apply(opened, SelectProjectFile("app/app.mbt"))
  let loaded = explorer_apply(
    selected,
    ProjectFileLoaded("app/app.mbt", Success("pub fn main {}\n")),
  )
  let mut seen_editors = false
  for run in shell_texts(explorer_draw(loaded, 1280.0, 800.0)) {
    if run.text == "打开的编辑器" {
      seen_editors = true
    }
  }
  assert_true(
    seen_editors,
    msg="有打开的 tab 时应出现「打开的编辑器」分区",
  )
}

///|
/// 工具栏图标动作的悬停提示写进状态栏（`icon_button` 的成熟口径）。
/// 这条锁定「四个图标不是不可发现的裸图标」。
test "explorer 工具栏图标悬停提示进状态栏" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(imported, SetLeftView(LeftProject))
  let hovering = explorer_apply(opened, HoverHint("新建文件夹"))
  let texts = shell_texts(explorer_draw(hovering, 1280.0, 800.0))
  let mut seen_hint = false
  for run in texts {
    if run.text == "新建文件夹" {
      seen_hint = true
    }
  }
  assert_true(seen_hint, msg="悬停提示应出现在状态栏")
}

///|
/// 「最近修改」底部条**不出现在资源管理器页**:改动记录已经是侧栏的
/// 「时间线」分区，再在底部留一条同内容的尾巴就是同一份数据画两遍。
///
/// 断言口径:同一条改动记录（target = "窗口1"）在资源管理器页出现在
/// **树的上方区域**（时间线分区）,在结构树页出现在**底部条**（y 更大）。
test "explorer 时间线取代底部最近修改条" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let seeded = push_recent(imported, "窗口1", "app.recent.align", false)
  let opened = explorer_apply(seeded, SetLeftView(LeftProject))
  let opened = explorer_apply(
    opened,
    ProjectOp(ToggleExplorerSection("timeline")),
  )
  let runs = shell_texts(explorer_draw(opened, 1280.0, 800.0))
  let mut timeline_y = -1.0
  let mut entry_y = -1.0
  for run in runs {
    if run.text == "时间线" {
      timeline_y = run.frame.origin.y
    }
    if run.text == "窗口1" {
      entry_y = run.frame.origin.y
    }
  }
  assert_true(
    timeline_y > 0.0,
    msg="资源管理器页应有「时间线」分区头",
  )
  assert_true(entry_y > 0.0, msg="时间线分区应列出改动记录")
  assert_true(
    entry_y > timeline_y,
    msg="记录应排在分区头之下（head y=\{timeline_y} vs entry y=\{entry_y}）",
  )
  // 结构树页:同一份改动记录出现在底部「最近修改」条（在树区之下）。
  // 注意 `SetLeftView` 是**开关**语义（再点当前项 = 收起），所以这里
  // 直接构造 left_view，不走消息——否则从 LeftProject 点 LeftTree 会
  // 落到 LeftHidden（面板整个收起，底部条一并消失）。
  let tree_page = { ..seeded, left_view: LeftTree, }
  let tree_runs = shell_texts(explorer_draw(tree_page, 1280.0, 800.0))
  let mut strip_y = -1.0
  for run in tree_runs {
    if run.text == "窗口1" {
      strip_y = run.frame.origin.y
    }
  }
  assert_true(
    strip_y > 0.0,
    msg="结构树页应保留底部「最近修改」条",
  )
  assert_true(
    strip_y > entry_y,
    msg="底部条比侧栏分区更靠下（条 y=\{strip_y} vs 分区 y=\{entry_y}）",
  )
}

///|
/// 单树多根:导入两个工程后,两棵顶层文件夹**同屏**出现（不再有上方
/// 工程列表 + 下方单树的二段结构）。
test "explorer 单树多根:两棵工程根同屏" {
  let services = @services.AppServices::new()
  let source_a = { ..explorer_source(), root: "/workspace/mod_a", }
  let source_b = {
    ..explorer_source(),
    root: "/workspace/mod_b",
    module_manifest: (
      #|name = "examples/other"
      #|version = "0.1.0"
      #|preferred_target = "native"
    ),
  }
  let scan : @project.WorkspaceScan = {
    root: "/workspace",
    loaded: [source_a, source_b],
    failed: [],
    root_dirs: [],
  }
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Workspace(scan)))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  // 两个成员同处工作区根之下（单树多根:一棵根,成员是它的子行）
  let rows = explorer_rows_for_test(opened)
  let mut seen_a = false
  let mut seen_b = false
  for r in rows {
    if r.contains(":mod_a") {
      seen_a = true
    }
    if r.contains(":mod_b") {
      seen_b = true
    }
  }
  assert_true(seen_a, msg="成员 mod_a 应可见")
  assert_true(seen_b, msg="成员 mod_b 应同屏可见（单树多根）")
}

///|
/// 大纲分区:打开一个文件后列出它的声明（名称 + 行号）,层级用缩进表达。
test "explorer 大纲分区列出当前文件符号" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(imported, SetLeftView(LeftProject))
  let opened = explorer_apply(
    opened,
    ProjectOp(ToggleExplorerSection("outline")),
  )
  let selected = explorer_apply(opened, SelectProjectFile("app/app.mbt"))
  let loaded = explorer_apply(
    selected,
    ProjectFileLoaded("app/app.mbt", Success("pub fn main {\n  let x = 1\n}\n")),
  )
  let runs = shell_texts(explorer_draw(loaded, 1280.0, 800.0))
  let mut seen_main = false
  let mut seen_x = false
  let mut main_x = -1.0
  let mut x_x = -1.0
  for run in runs {
    // 只取左栏（大纲分区）里的同名 run：编辑区正文也会画出 main / x。
    if run.frame.origin.x < 300.0 && run.text == "main" {
      seen_main = true
      main_x = run.frame.origin.x
    }
    if run.frame.origin.x < 300.0 && run.text == "x" {
      seen_x = true
      x_x = run.frame.origin.x
    }
  }
  assert_true(seen_main, msg="大纲应列出 fn main")
  assert_true(seen_x, msg="大纲应列出嵌套的 let x")
  assert_true(
    x_x > main_x,
    msg="嵌套符号的缩进应比顶层深（main x=\{main_x} vs x x=\{x_x}）",
  )
}

///|
/// 「打开的编辑器」分区:列出了打开的 tab,脏 tab 带脏标记。
test "explorer 打开的编辑器分区" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(imported, SetLeftView(LeftProject))
  let opened = explorer_apply(
    opened,
    ProjectOp(ToggleExplorerSection("editors")),
  )
  let selected = explorer_apply(opened, SelectProjectFile("app/app.mbt"))
  let loaded = explorer_apply(
    selected,
    ProjectFileLoaded("app/app.mbt", Success("pub fn main {}\n")),
  )
  let clean = shell_texts(explorer_draw(loaded, 1280.0, 800.0))
  let mut seen_tab = false
  let mut dirty_dot = false
  for run in clean {
    // 分区里的文件名（不带头部标签）
    if run.text == "app.mbt" {
      seen_tab = true
    }
    if run.text == "●" {
      dirty_dot = true
    }
  }
  assert_true(seen_tab, msg="打开的编辑器应列出 app.mbt")
  assert_false(dirty_dot, msg="未编辑的 tab 不应有脏标记")
  // 编辑后出现脏标记
  let edited = explorer_apply(
    loaded,
    WorkbenchOp(@wb.EditDocument("file:app/app.mbt", "pub fn main { 1 }\n")),
  )
  let mut dirty_after = false
  for run in shell_texts(explorer_draw(edited, 1280.0, 800.0)) {
    if run.text == "●" {
      dirty_after = true
    }
  }
  assert_true(dirty_after, msg="编辑后应出现脏标记")
}

///|
/// M3:全局编辑区 tab——常驻 Studio tab 不可关闭;文件 tab 带脏点;切换透视
/// 不切走活动文件;AI 模式隐藏文件 tab 但保留文档状态。
test "全局 editor tab:Studio 常驻、文件脏点与 AI 隐藏" {
  let services = @services.AppServices::new()
  let base = update_with_services(
      initial_model(),
      SetPerspective(PsCode),
      services,
    ).0
  // Studio tab 常驻:关闭请求是 no-op
  let closed = update_with_services(
      base,
      WorkbenchOp(@wb.CloseDocument(@wb.STUDIO_DOC_ID)),
      services,
    ).0
  assert_eq(closed.workbench.docs.entries.length(), 1)
  assert_eq(
    closed.workbench.docs.active_entry().unwrap().doc.id,
    @wb.STUDIO_DOC_ID,
  )
  // 打开并编辑文件 → 文件 tab 出现脏点
  let selected = update_with_services(
      base,
      SelectProjectFile("app/app.mbt"),
      services,
    ).0
  let loaded = update_with_services(
      selected,
      ProjectFileLoaded("app/app.mbt", Success("pub fn main {}\n")),
      services,
    ).0
  let edited = update_with_services(
      loaded,
      WorkbenchOp(@wb.EditDocument("file:app/app.mbt", "pub fn main { 1 }\n")),
      services,
    ).0
  let mut seen_dirty_tab = false
  let mut seen_studio = false
  for run in shell_texts(shell_draw(edited, 1280.0, 800.0)) {
    if run.text == "Studio" {
      seen_studio = true
    }
    if run.text == "app.mbt ●" {
      seen_dirty_tab = true
    }
  }
  assert_true(seen_studio, msg="常驻 Studio tab 应出现")
  assert_true(seen_dirty_tab, msg="脏文件 tab 应带脏点")
  // 切到可视化透视:活动文件不变（透视只决定 Studio 文档的 provider）
  let visual = update_with_services(edited, SetPerspective(PsVisual), services).0
  assert_eq(
    visual.workbench.docs.active_entry().unwrap().doc.id,
    "file:app/app.mbt",
  )
  // AI 模式:中心是会话流,文件 tab 隐藏但文档状态保留
  let ai = update_with_services(edited, SetPerspective(PsAi), services).0
  assert_eq(
    ai.workbench.docs.active_entry().unwrap().doc.id,
    "file:app/app.mbt",
  )
  let mut ai_file_tab = false
  for run in shell_texts(shell_draw(ai, 1280.0, 800.0)) {
    if run.text == "app.mbt ●" {
      ai_file_tab = true
    }
  }
  assert_false(ai_file_tab, msg="AI 模式不应画文件 tab")
  // 关闭干净文件 tab → 回到 Studio 文档
  let clean = update_with_services(
      loaded,
      WorkbenchOp(@wb.CloseDocument("file:app/app.mbt")),
      services,
    ).0
  assert_true(clean.workbench.docs.file_entries().is_empty())
  assert_eq(
    clean.workbench.docs.active_entry().unwrap().doc.id,
    @wb.STUDIO_DOC_ID,
  )
}

///|
/// 就地新建文件:输入行出现在**目标目录之下**（不是面板顶部）,
/// 且新文件的提交目标带目录前缀。
test "explorer 就地新建输入行跟随目标目录" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  // 在 app/ 下新建:输入行应排在 app 目录行之后、app 的文件之前
  let creating = explorer_apply(opened, ProjectOp(FileCreateAt("app")))
  let runs = shell_texts(explorer_draw(creating, 1280.0, 800.0))
  // 行序判据用「模块根行 → app 目录行 → 输入行 → app 的第一个文件」这条
  // 结构链,不要用绝对 y 阈值:面板内边距/搜索框一变,阈值就失效,
  // 而真正要锁住的是输入行插在目录行与其文件之间。
  let mut module_y = -1.0
  let mut app_y = -1.0
  let mut input_y = -1.0
  let mut first_file_y = -1.0
  for run in runs {
    // 模块名在底部状态栏也会出现一次,取**最上面**的那次才是树上的根行。
    if run.text.contains("examples/counter") &&
      (module_y < 0.0 || run.frame.origin.y < module_y) {
      module_y = run.frame.origin.y
    }
  }
  for run in runs {
    if run.text == "app" && run.frame.origin.y > module_y {
      app_y = run.frame.origin.y
    }
    if run.text == "name" {
      // text_field 的 placeholder
      input_y = run.frame.origin.y
    }
    if run.text == "app.mbt" {
      first_file_y = run.frame.origin.y
    }
  }
  assert_true(
    app_y > 0.0,
    msg="app 目录行应可见（模块根行 y=\{module_y}）",
  )
  assert_true(
    input_y > 0.0,
    msg="就地输入行应可见（placeholder 未渲染说明输入行没挂上）",
  )
  assert_true(
    app_y < input_y,
    msg="输入行应在 app 目录行之下（app y=\{app_y} vs input y=\{input_y}）",
  )
  assert_true(
    first_file_y < 0.0 || input_y < first_file_y,
    msg="输入行应在 app 的文件之前（input y=\{input_y} vs app.mbt y=\{first_file_y}）",
  )
}

///|
/// 悬停行才有行内动作:非悬停行的尾部动作格是空白占位（宽度始终预留,
/// 否则标签会在鼠标扫过整棵树时左右跳动）。
test "explorer 行内动作只在悬停行出现" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  // 没有悬停时,删除图标不应出现在任何行（`Trash` 图标只在悬停行的
  // trailing 里构造）。用带标签的语义节点数间接断言:没有悬停 → 动作
  // 视图不构造。
  let resting = explorer_draw(opened, 1280.0, 800.0)
  let mut resting_paths = 0
  for command in resting {
    match command {
      @core.DrawPath(_) => resting_paths = resting_paths + 1
      _ => ()
    }
  }
  // 悬停某个文件行 → 该行的 ✎ / 🗑 出现（路径数增加）
  let file_key = "file-0:app/app.mbt"
  let hovering = explorer_apply(opened, ProjectOp(ExplorerHover(file_key)))
  let hovered = explorer_draw(hovering, 1280.0, 800.0)
  let mut hovered_paths = 0
  for command in hovered {
    match command {
      @core.DrawPath(_) => hovered_paths = hovered_paths + 1
      _ => ()
    }
  }
  assert_true(
    hovered_paths > resting_paths,
    msg="悬停行应多出动作图标（静息 \{resting_paths} vs 悬停 \{hovered_paths}）",
  )
}

///|
/// 缩进导轨:深层文件的导轨条数多于浅层（导轨路径数随深度增长）。
/// 导轨是唯一不用读文字就能跟住层级的线索。
test "explorer 缩进导轨随深度增加" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  // 收集每一行左侧的竖线（宽 1pt 的窄填充）：浅层文件（根下）与深层文件
  // （docs/guide.md）都比对同一口径。
  let runs = shell_texts(explorer_draw(opened, 1280.0, 800.0))
  let mut root_file_y = -1.0
  let mut deep_file_y = -1.0
  for run in runs {
    if run.text == "moon.mod" {
      root_file_y = run.frame.origin.y
    }
    if run.text == "guide.md" {
      deep_file_y = run.frame.origin.y
    }
  }
  assert_true(root_file_y > 0.0, msg="根文件应可见")
  assert_true(deep_file_y > 0.0, msg="深层文件应可见")
  // 深层文件的 x 应比根文件更靠右（缩进）
  let mut root_x = -1.0
  let mut deep_x = -1.0
  for run in runs {
    if run.text == "moon.mod" {
      root_x = run.frame.origin.x
    }
    if run.text == "guide.md" {
      deep_x = run.frame.origin.x
    }
  }
  assert_true(
    deep_x > root_x,
    msg="深层文件应缩进更多（moon.mod x=\{root_x} vs guide.md x=\{deep_x}）",
  )
  assert_eq(explorer_guide_line_count(1), 1, msg="一层缩进一条导轨")
  assert_eq(explorer_guide_line_count(2), 2, msg="两层缩进两条导轨")
}

///|
/// 大 fixture：单包 80 个文件（内容 ~1920pt,远超左栏视口）,用于事件级
/// 滚动复现。
fn explorer_big_source() -> @project.ProjectSource {
  let mod_text =
    #|name = "examples/counter"
    #|version = "0.1.0"
    #|preferred_target = "native"
  let pkg =
    #|import {
    #|  "wzzc-dev/moui",
    #|}
  let files : Array[String] = []
  let mut index = 0
  while index < 80 {
    files.push("file_\{index}.mbt")
    index = index + 1
  }
  @project.ProjectSource::{
    root: "/root",
    module_manifest: mod_text,
    package_sources: [("big", pkg, false, files)],
    dirs: [@project.ScannedDir::{ rel_path: "big", files, }],
  }
}

///|
/// 事件级滚动回归：真实 runtime + 真实滚轮 PointerEvent（此前只发消息,
/// 绕过了 scroll_container 的钳制/视口路径,漏掉真实发散点）。
/// 断言三段:滚到底最后文件可见、途中不空白、滚回顶首文件可见。
test "explorer 事件级滚动:到底/回顶行均可见" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_big_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  let studio_program = @moui.Program::new_with_environment(
    init=() => (opened, @moui.Effect::none()),
    update=(current, msg) => update_pure(current, msg),
    view=(current, env) => view_with_viewport(current, env.viewport_size()),
  )
  let runtime = @runtime.new_program_with_dimensions(
    program=studio_program,
    width=1280.0,
    height=800.0,
  )
  // 向下滚 24 × 300pt（远超 ~1200pt 的可滚范围,必被钳到底）
  let mut step = 0
  while step < 24 {
    runtime.dispatch_event(
      @core.Pointer(
        @core.PointerEvent::new(
          position=@core.Point::new(x=100.0, y=400.0),
          phase=@core.Move,
          wheel_delta=@core.Point::new(x=0.0, y=-300.0),
        ),
      ),
    )
    step = step + 1
  }
  let mut visible_files = 0
  let mut last_seen = false
  for run in shell_texts(runtime.draw_commands()) {
    if run.text.contains("file_") {
      visible_files = visible_files + 1
    }
    if run.text == "file_79.mbt" {
      last_seen = true
    }
  }
  assert_true(
    visible_files > 0,
    msg="滚动后应有文件行可见（实际 0 行）",
  )
  assert_true(last_seen, msg="滚到底后最后一个文件应可见")
  // 滚回顶
  let mut up = 0
  while up < 24 {
    runtime.dispatch_event(
      @core.Pointer(
        @core.PointerEvent::new(
          position=@core.Point::new(x=100.0, y=400.0),
          phase=@core.Move,
          wheel_delta=@core.Point::new(x=0.0, y=300.0),
        ),
      ),
    )
    up = up + 1
  }
  let mut first_seen = false
  for run in shell_texts(runtime.draw_commands()) {
    if run.text == "file_0.mbt" {
      first_seen = true
    }
  }
  assert_true(first_seen, msg="滚回顶后第一个文件应可见")
}

///|
/// M1-2 验收核心:重放画布把解析帧里的 DrawText 真画出来——
/// 「counter 导入 → 预览构建 → 画布出帧」的最后一环。
test "预览工作区重放帧:JSON 命令真画到画布上" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(compile_track_available=true),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let report = @build.BuildReport::{
    kind: BkFramePreview,
    ok: true,
    exit_code: 0,
    output: "__STUDIO_PREVIEW_V1__\n{\"version\":\"1\",\"width\":640.0,\"height\":480.0,\"commands\":[[\"FillRect\",{\"origin\":{\"x\":0,\"y\":0},\"size\":{\"width\":640,\"height\":480}},{\"r\":1,\"g\":1,\"b\":1,\"a\":1}],[\"DrawText\",{\"text\":\"MoUI Counter\",\"frame\":{\"origin\":{\"x\":44,\"y\":10},\"size\":{\"width\":200,\"height\":20}},\"font\":{\"families\":{\"families\":[\"SystemUi\"]},\"size\":13,\"weight\":400,\"style\":\"Normal\",\"variations\":[]},\"color\":{\"r\":0.1,\"g\":0.1,\"b\":0.1,\"a\":1},\"align\":\"TextStart\"}]],\"semantics\":[]}",
    diagnostics: [],
    web_root: "",
    web_index_rel: "",
    artifact_path: "",
  }
  let finished = update_with_services(
      imported,
      ProjectBuildFinished(BkFramePreview, Ok(report)),
      services,
    ).0
  assert_true(finished.preview_frame is Some(_))
  let opened = explorer_apply(finished, SetWorkSpace(WsPreview))
  let commands = explorer_draw(opened, 1280.0, 800.0)
  // 重放画布必须画出帧里的文本(而非 Studio 自己的 chrome 文案):
  // DrawText 的 text 与帧 JSON 逐字一致。
  let mut replayed = false
  for run in shell_texts(commands) {
    if run.text == "MoUI Counter" && run.frame.origin.x == 44.0 {
      replayed = true
    }
  }
  assert_true(replayed, msg="帧里的 DrawText 应被重放到画布(x=44)")
}

///|
/// M1-3:语义投影 + 命中测试(最深匹配)。
test "语义投影与命中:点标题选中,点空白取消" {
  let frame = match @run.parse_preview_frame(preview_payload()) {
    Ok(frame) => frame
    Err(msg) => fail("载荷应可解析:\{msg}")
  }
  let nodes = @run.semantic_hit_nodes(frame)
  // fixture 语义:标题节点(MoUI Studio)+ 无 label 的容器节点
  assert_true(nodes.length() >= 2)
  // 命中标题(x=100,y=15 在 frame {44,10,96,20} 内)
  let mut title_index = -1
  let mut i = 0
  for node in nodes {
    if node.label == "MoUI Studio" {
      title_index = i
    }
    i = i + 1
  }
  assert_true(title_index >= 0, msg="fixture 应含标题节点")
  assert_eq(@run.semantic_hit_index(nodes, 100.0, 15.0), title_index)
  // 画布坐标系之外的点未命中(容器节点覆盖整个 640×480)
  assert_eq(@run.semantic_hit_index(nodes, 700.0, 500.0), -1)
}

///|
/// 标题栏 `⋯` 溢出菜单:点开就展开一组动作（收起时完全不占高）。
///
/// 截图里标题栏右上角那一个就是它;没有它,四个创建动作之外的命令
/// （导入 / 刷新 / 全部折叠的第二个入口）在侧栏里没有落点。
test "explorer 溢出菜单开合" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(imported, SetLeftView(LeftProject))
  // 收起:菜单里的「全部折叠」不应出现（它只在菜单里,工具栏是图标）
  let mut closed_collapse = false
  for run in shell_texts(explorer_draw(opened, 1280.0, 800.0)) {
    if run.text == "全部折叠" {
      closed_collapse = true
    }
  }
  assert_false(closed_collapse, msg="菜单收起时不应有菜单文字行")
  // 展开
  let menu = explorer_apply(opened, ProjectOp(ToggleExplorerMenu))
  let mut seen_collapse = false
  let mut seen_new_folder = false
  for run in shell_texts(explorer_draw(menu, 1280.0, 800.0)) {
    if run.text == "全部折叠" {
      seen_collapse = true
    }
    if run.text == "新建文件夹" {
      seen_new_folder = true
    }
  }
  assert_true(seen_collapse, msg="菜单展开后应列出「全部折叠」")
  assert_true(
    seen_new_folder,
    msg="菜单展开后应列出「新建文件夹」",
  )
  // 再点收起
  let closed = explorer_apply(menu, ProjectOp(ToggleExplorerMenu))
  let mut after_close = false
  for run in shell_texts(explorer_draw(closed, 1280.0, 800.0)) {
    if run.text == "全部折叠" {
      after_close = true
    }
  }
  assert_false(after_close, msg="再点一次应收起菜单")
}

///|
/// 目录行悬浮 ＋ 的目标目录:在哪一层按新建,就建在哪一层。
///
/// 回归:早先「新建文件夹」不带目录（`FolderCreateStart`）,目录行上按它
/// 会把文件夹默默建到**工程根**——树上看不出差别,直到发现文件没在点的那
/// 个文件夹里。
test "explorer 目录行新建:目标目录跟随所在层" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  // 目录行的「新建文件」
  let file_in_app = explorer_apply(imported, ProjectOp(FileCreateAt("app")))
  assert_eq(file_in_app.project_state.file_create_dir, "app")
  assert_eq(
    join_rel(file_in_app.project_state.file_create_dir, "x.mbt"),
    "app/x.mbt",
  )
  // 目录行的「新建文件夹」——必须同样落在 app/
  let folder_in_app = explorer_apply(imported, ProjectOp(FolderCreateAt("app")))
  assert_true(folder_in_app.project_state.folder_create_open)
  assert_eq(
    folder_in_app.project_state.file_create_dir,
    "app",
    msg="新建文件夹的目标目录应是所在层,不是工程根",
  )
  assert_eq(
    join_rel(folder_in_app.project_state.file_create_dir, "newdir"),
    "app/newdir",
  )
  // 工具栏（不带目录）= 工程根
  let folder_at_root = explorer_apply(imported, ProjectOp(FolderCreateAt("")))
  assert_eq(folder_at_root.project_state.file_create_dir, "")
  assert_eq(
    join_rel(folder_at_root.project_state.file_create_dir, "newdir"),
    "newdir",
  )
}

///|
/// 两个新建入口互斥:开着文件输入行时点「新建文件夹」,不该同时出现两行
/// 输入（同一时刻只有一个「正在新建的东西」）。
test "explorer 新建文件与新建文件夹互斥" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let file_open = explorer_apply(imported, ProjectOp(FileCreateAt("app")))
  assert_true(file_open.project_state.file_create_open)
  let then_folder = explorer_apply(file_open, ProjectOp(FolderCreateAt("app")))
  assert_true(then_folder.project_state.folder_create_open)
  assert_false(
    then_folder.project_state.file_create_open,
    msg="打开文件夹输入行应关掉文件输入行",
  )
  let then_file = explorer_apply(then_folder, ProjectOp(FileCreateAt("app")))
  assert_true(then_file.project_state.file_create_open)
  assert_false(
    then_file.project_state.folder_create_open,
    msg="反向也应互斥",
  )
}

///|
/// **用户反馈回归**:工作区导入时,根目录**自己**的文件必须出现在树上。
///
/// 根因:moon.work 只列成员目录,根上的 `moon.work`/`README.md`/`gradlew`…
/// 不属于任何成员。早先的实现把每个成员各自当成顶层行,根这一层根本不存在
/// ——实测 `gradlew` 的 owner 数为 0,树上一个位置都没有。
///
/// 正确的形态（截图口径）:**一棵工作区根行**,成员是它的子目录,根文件与
/// 成员目录**同级**。
test "explorer 工作区:根目录自己的文件可见" {
  let services = @services.AppServices::new()
  let source_a = { ..explorer_source(), root: "/ws/mod_a", }
  let scan : @project.WorkspaceScan = {
    root: "/ws",
    loaded: [source_a],
    failed: [],
    root_dirs: [
      @project.ScannedDir::{
        rel_path: "",
        files: ["gradlew", "moon.work", "README.md"],
      },
      @project.ScannedDir::{ rel_path: "docs", files: ["guide.md"], },
    ],
  }
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Workspace(scan)))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  let rows = explorer_rows_for_test(opened)
  // 树上有工作区根行（下标 -1）
  let mut root_row = false
  for r in rows {
    if r == "root--1" {
      root_row = true
    }
  }
  assert_true(root_row, msg="应有工作区根行")
  // 根上的每个文件都有一行（这是本次修复的核心断言）
  for needle in ["gradlew", "moon.work", "README.md"] {
    let mut found = false
    for r in rows {
      if r == "file--1:" + needle {
        found = true
      }
    }
    assert_true(found, msg="根目录文件应有一行:" + needle)
  }
  // 非成员目录也能展开
  let mut docs_row = false
  let mut guide_row = false
  for r in rows {
    if r == "dir--1:docs" {
      docs_row = true
    }
    if r == "file--1:docs/guide.md" {
      guide_row = true
    }
  }
  assert_true(docs_row, msg="根下的非成员目录应有行")
  assert_true(guide_row, msg="非成员目录里的文件应可见")
  // 成员目录是根的子行,不是另一棵顶层树;键带成员在树上的 rel
  let mut member_row = false
  for r in rows {
    if r == "dir-0:mod_a" {
      member_row = true
    }
  }
  assert_true(member_row, msg="成员应是工作区根的子目录行")
}

///|
/// **用户反馈回归**:树行左侧不得出现不透明的实心方块。
///
/// 两个坑都踩过,这条测试把结论钉死:
/// 1. 给 divider 套**裸 container** → 裸 container 无背景、回落环境面板色,
///    每格背后多出 12×16 的深灰圆角块（截图里那排黑方块）。
/// 2. 直接给 divider 加 `.frame(width=12, height=16)` → 竖放 divider
///    **填满可用宽**,整格变成实心竖条（比 1 更糟）。
///
/// 正解:`center(width=12, height=16, 透明背景)` + 内部 1pt divider。
/// 这条断言「导轨格里没有不透明填充」+「1pt 细线确实还在」两件事。
test "explorer 缩进导轨:透明占位格 + 1pt 细线" {
  let services = @services.AppServices::new()
  let imported = update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Single(explorer_source())))),
      services,
    ).0
  let opened = explorer_apply(
    explorer_tree_expanded(imported),
    SetLeftView(LeftProject),
  )
  let commands = explorer_draw(opened, 1280.0, 800.0)
  // 导轨格范围（x ∈ [50, 90)）内不得有不透明填充
  let mut opaque_blocks = 0
  for command in commands {
    match command {
      @core.FillRoundedRectBrush(rounded, brush) =>
        if rounded.rect.origin.x >= 50.0 && rounded.rect.origin.x < 90.0 {
          match brush {
            @core.Brush::Solid(color) =>
              if color.a > 0.5 {
                opaque_blocks = opaque_blocks + 1
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  assert_eq(
    opaque_blocks,
    0,
    msg="导轨格里不应有不透明实心块（裸 container 回落底色 / divider 被拉伸都会造成它）",
  )
  // 1pt 细线必须还在（否则"没有方块"是靠在导轨没画出来）
  let mut guide_lines = 0
  for command in commands {
    match command {
      @core.FillRect(rect, _) =>
        if rect.size.width == 1.0 &&
          rect.size.height > 10.0 &&
          rect.origin.x < 100.0 {
          guide_lines = guide_lines + 1
        }
      _ => ()
    }
  }
  assert_true(guide_lines > 0, msg="缩进导轨的 1pt 细线应存在")
  // 行的箭头位置同样不能是裸 container（同一个缺陷类）
  let mut opaque_twisty = 0
  for command in commands {
    match command {
      @core.FillRoundedRectBrush(rounded, brush) =>
        if rounded.rect.origin.x >= 60.0 &&
          rounded.rect.origin.x <= 70.0 &&
          rounded.rect.size.width >= 13.0 {
          match brush {
            @core.Brush::Solid(color) =>
              if color.a > 0.5 {
                opaque_twisty = opaque_twisty + 1
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  assert_eq(opaque_twisty, 0, msg="箭头热区不应有实心底块")
  // 工具栏图标同样不能有裸 container 的回落底（同一缺陷类的第三处）
  let mut opaque_toolbar = 0
  for command in commands {
    match command {
      @core.FillRoundedRectBrush(rounded, brush) =>
        if rounded.rect.size.width == 22.0 && rounded.rect.size.height == 18.0 {
          match brush {
            @core.Brush::Solid(color) =>
              if color.a > 0.5 {
                opaque_toolbar = opaque_toolbar + 1
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  assert_eq(
    opaque_toolbar,
    0,
    msg="工具栏图标的内格不应有实心底块",
  )
}

///|
/// **用户反馈回归**:`examples/` 这样的中间目录必须是**可折叠的节点**,
/// 不能把里面的成员平铺到顶层。
///
/// 根因:成员路径可以是多段的（`examples/terminal`、`benchmarks/full_cycle`）。
/// 早先按 `model.project_state.projects` 遍历、一个成员一行,于是 `examples/terminal`
/// 变成顶层一行,而 `examples` 这个中间目录**根本不存在**——用户看到的是
/// 「examples 下的模块直接显示,收起 examples 收不掉里面」。
///
/// 这条断言三件事:① `examples` 有目录行;② 折叠它之后,归属
/// `examples/*` 成员的**所有行都消失**;③ 折叠前它们确实在（否则判据本身
/// 失效,测试会变成空断言）。
test "explorer 嵌套成员:中间目录可折叠" {
  let services = @services.AppServices::new()
  // 两个成员:一个在 examples/ 下,一个在顶层
  let nested = {
    ..explorer_source(),
    root: "/ws/examples/terminal",
    module_manifest: (
      #|name = "examples/terminal"
      #|version = "0.1.0"
      #|preferred_target = "native"
    ),
  }
  let top = { ..explorer_source(), root: "/ws/tools", }
  let scan : @project.WorkspaceScan = {
    root: "/ws",
    loaded: [nested, top],
    failed: [],
    root_dirs: [],
  }
  let imported = explorer_tree_expanded(
    update_with_services(
      initial_model(),
      ProjectScanCompleted(Success(Ok(Workspace(scan)))),
      services,
    ).0,
  )
  let rows = explorer_rows_for_test(imported)
  // ① examples 中间目录行存在
  let mut has_examples = false
  for r in rows {
    if r == "dir--1:examples" {
      has_examples = true
    }
  }
  assert_true(
    has_examples,
    msg="examples 应是可折叠的中间目录行（不能把成员平铺到顶层）",
  )
  // 顶层成员（tools）仍是工作区根的直接子行
  let mut has_tools = false
  for r in rows {
    if r == "dir-0:tools" || r == "dir-1:tools" {
      has_tools = true
    }
  }
  assert_true(has_tools, msg="顶层成员应挂在工作区根之下")
  // examples/terminal 应在 examples 之下,不是顶层
  let mut nested_key = ""
  for r in rows {
    if r.contains(":examples/terminal") {
      nested_key = r
    }
  }
  assert_true(
    nested_key != "",
    msg="examples/terminal 成员行应存在（且在 examples 之下）",
  )
  // ② 折叠 examples → 该成员所有行消失
  let collapsed = explorer_updates(
    imported,
    ProjectOp(ToggleProjectDirAt(@proj.WORKSPACE_ROOT_INDEX, "examples")),
  )
  let after = explorer_rows_for_test(collapsed)
  let mut nested_rows_after = 0
  for r in after {
    if r.contains("examples/terminal") {
      nested_rows_after = nested_rows_after + 1
    }
  }
  assert_eq(
    nested_rows_after,
    0,
    msg="折叠 examples 后,它下面的成员行应全部收起",
  )
  // ③ 折叠前确实有（判据有效）
  let mut nested_rows_before = 0
  for r in rows {
    if r.contains("examples/terminal") {
      nested_rows_before = nested_rows_before + 1
    }
  }
  assert_true(
    nested_rows_before > 0,
    msg="折叠前 examples/terminal 的行应存在（否则上一条断言是空的）",
  )
  // 顶层成员不受影响
  let mut tools_after = false
  for r in after {
    if r.contains("tools") {
      tools_after = true
    }
  }
  assert_true(tools_after, msg="折叠 examples 不应影响顶层成员")
}

///|
/// 依次派发多条消息（纯转移）。
fn explorer_updates(model : Model, msg : Msg) -> Model {
  explorer_apply(model, msg)
}
