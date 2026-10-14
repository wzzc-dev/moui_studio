///|
/// 新建工程骨架（folder projects）的**生成面**：把「新建示例项目」摊成一串
/// 「绝对路径 → 内容」的落盘计划——moon.mod + 可编译的 app 包（导出 bundle
/// 同款内核快照 + 生成源码）+ 平台入口包（`native_app/` 与 `web_wasm/`）+
/// IR 快照。壳侧（`moui_studio/app/new_project.mbt`）只留草稿状态机与逐文件
/// 写盘 Effect，这里零状态、零 Effect、零 Model。
///
/// 三个既有事实在这里汇合，不新造格式：
/// 1. 内核（domain/ir、studio_lang、codec、compiled_runtime、runner）逐字节
///    复用导出表（`@export.kernel_file_sources`）——`wzzc-dev/moui_studio`
///    未上注册表，生成的工程只能自包含；漂移由 export_test 锁定。
/// 2. 事件真源 handlers.mbt 走 `@export.generated_handlers_mbt`，与代码工程
///    写盘（`EvCodeProjectWrite`）同一条生成链、同一个路径。
/// 3. IR 快照存 `<root>/.studio/program.json`（`.studio/` 被工程扫描跳过，
///    与预览 harness 同目录惯例）；磁盘→IR 反解析是 workbench M6 范围，
///    快照是它落地前的恢复机制。

///|
/// IR 快照在工程内的固定路径（相对工程根）。
pub const PROGRAM_SNAPSHOT_REL : String = ".studio/program.json"

///|
/// 文件夹名 → 模块名：与导出器同一口径（`@export.sanitize_name`）——非字母数字
/// 折叠为连字符，退化输入给可用兜底名，数字开头加前缀。模块名同时是生成工程里
/// 包导入路径的前缀，非法名会让整个工程解析不了。
pub fn module_name_from_root(root : String) -> String {
  let basename = match root.rev_find("/") {
    Some(index) => root[index + 1:].to_owned()
    None => root
  }
  @export.sanitize_name(basename)
}

///|
/// 新建工程的落盘文件集：路径 → 内容。`module_name` 来自文件夹名；
/// `program` 是模板 IR（决定 handlers/project_data 与 IR 快照）。
pub fn skeleton_files(
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
    (
      "\{root}/domain/studio_lang/moon.pkg",
      @export.studio_lang_pkg(module_name),
    ),
  )
  files.push(("\{root}/domain/codec/moon.pkg", @export.codec_pkg(module_name)))
  files.push(
    (
      "\{root}/compiled_runtime/moon.pkg",
      @export.compiled_runtime_pkg(module_name),
    ),
  )
  files.push(("\{root}/app/moon.pkg", @export.app_pkg(module_name)))
  for pair in @export.kernel_file_sources() {
    files.push(("\{root}/\{pair.0}", pair.1))
  }
  files.push(("\{root}/app/project_data.mbt", @export.project_data_mbt(json)))
  files.push(("\{root}/app/handlers.mbt", @export.generated_handlers_mbt(json)))
  // form.mbt 不进应用骨架：render_form 产出的 `on_click=<handler 函数名>`
  // 引用编译轨函数，与 @views 的 Msg 参数类型不兼容（workbench M6 的
  // 布局真源语义未落地）——放了必编不过，不如诚实不含。
  // 平台入口包（与导出 bundle 同一套模板）：没有它们，新建的工程在 Studio
  // 之外 `moon run` 无处可跑——组合根 `app` 只声明 `program()`，
  // 窗口/渲染器/事件泵全部在入口包里接线。
  files.push(
    ("\{root}/native_app/moon.pkg", @export.native_app_pkg(module_name)),
  )
  files.push(("\{root}/native_app/main.mbt", @export.native_app_main()))
  files.push(("\{root}/web_wasm/moon.pkg", @export.web_pkg(module_name)))
  files.push(("\{root}/web_wasm/main.mbt", @export.web_main()))
  files.push(("\{root}/web_wasm/abi.mbt", @export.abi_mbt()))
  files.push(
    ("\{root}/web_wasm/index.html", @export.web_index_html(module_name)),
  )
  files.push(("\{root}/\{PROGRAM_SNAPSHOT_REL}", json))
  files
}
