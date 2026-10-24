/// MoUI Studio TEA 模型：程序 IR + 界面语言 + 三模式 + 运行态 +
/// 待采纳提案 + provider 会话内存。纯数据，无服务无视图。

///|
pub(all) enum Mode {
  ModeDesign
  ModeBlocks
  ModeCode
  ModePreview
  ModeHelp
  ModeRun
}

///|
/// 产物旁路动作的种类：决定成功 toast 的文案。
/// 三个动作共用一条回执消息（`ArtifactActionDone`），来源必须显式带上。
pub(all) enum ArtifactAction {
  ArtifactCopy
  ArtifactReveal
  ArtifactLaunch
  /// 时间线消息复制（对白转录）：复用同一条回执通道，文案区分
  ArtifactAiCopy
  /// 代码块级复制（目标图右栏）：同上，文案再分一档
  ArtifactAiCodeCopy
}

///|
/// 双轨：解释轨（沙箱指令机）与编译轨（真编译闭包执行面）。

///|
/// 运行域状态类型转发(S3b 出壳,plugins/run):解释轨/编译轨运行态。
pub type RunModel = @run.RunModel

///|
pub type CompiledRun = @run.CompiledRun

///|
pub(all) enum RunTrack {
  Interpret
  Compile
}

///|
/// 待采纳提案类型已随 S4b AI 视图迁入 plugins/ai/ai_state.mbt；
/// app 保留公开别名，既有 update 引用零改动。
pub type PendingProposal = @ai.PendingProposal

///|
/// 撤销深度上限（快照式 undo 栈，超过丢弃最旧条目）。
pub const UNDO_DEPTH : Int32 = 50

///|
/// 最近修改保留条数（设计稿列表可见 4 条；多留几条供滚动）。
pub const RECENT_LIMIT : Int32 = 24

///|
/// 运行审计保留条数（会话内时间线，超出丢最旧）。
pub const AUDIT_LIMIT : Int32 = 200

///|
/// Console 日志保留条数。
pub const LOG_LIMIT : Int32 = 400

///|
/// 同屏 toast 上限（旧的在渲染层取最近 N 条）。
pub const TOAST_LIMIT : Int32 = 3

///|
/// toast 自动消失秒数（ToastTick 每秒老化一次）。
pub const TOAST_SECONDS : Int32 = 4

///|
/// 一条 toast：文案 + 是否警告色 + 已存活秒数。
pub(all) struct ToastEntry {
  text : String
  warning : Bool
  age : Int32
}

///|
/// AI 会话卡保留条数。
pub const AI_CARD_LIMIT : Int32 = 24

///|
/// 积木画布单块行高。**引用几何层的同一常量**（`@blk.BLOCKS_ROW_HEIGHT`）
/// ——行距 = 行高是 Scratch 堆叠咬合的前提，两处各写一个数就会悄悄分叉。
pub const BLOCK_ROW_HEIGHT : Double = @blk.BLOCKS_ROW_HEIGHT

///|
/// 撤销条目：变更前的编辑快照（程序 + 选中态 + 代码草稿）。
/// coalesce_key 非空且与栈顶相同时连续同类编辑合并为一个还原点。
pub(all) struct UndoEntry {
  program : @ir.StudioProgram
  selected_control : String
  selected_handler : String
  code_draft : String
  coalesce_key : String
}

///|
pub type ProposalRecord = @ai.ProposalRecord

///|
/// 设计画布拖拽态：被拖控件 + 拖拽种类（移动/缩放）。
pub(all) struct DragState {
  control : String
  kind : DragKind
}

///|
/// 积木拖拽态(S5 出壳,plugins/blocks)：类型转发，构造点与字段读取不变。
pub type BlocksDragState = @blk.BlocksDragState

///|
/// 拖拽种类：移动（带按下点相对控件原点的偏移，拖拽跟随不跳变）/
/// 缩放（从该角拖拽，对角固定）。
pub(all) enum DragKind {
  Move(Int32, Int32)
  Resize(@ir.DragCorner)
}

///|
/// 中心工作区：可视化工作区（Live App / 积木多窗格）/ 代码工作区 / 空舞台。
/// 与旧 Mode 的关系：Mode 仍是「进入哪种工作台」的粗粒度路由（含运行、
/// 帮助、MoonBit 预览三个全屏页），WorkSpace 是可视化/代码两个编辑工作区
/// 内部的窗格编排状态——设计稿把三视图统一进一个可视工作区，切换成本从
/// 「换模式」降为「点图标」。
pub(all) enum WorkSpace {
  WsVisual
  WsCode
  /// 工程预览(M1):headless 帧重放画布(M2/M3 加 web/native 模式)
  WsPreview
  WsEmpty
} derive(Eq)

///|
pub extend WorkSpace with Eq::{not_equal, equal}

///|
/// 预览模式(M2-2):画布快览(模式一)/ web 实时(模式二,webview)。

///|
/// 预览数据层(S3a 出壳,plugins/run):帧结构与命中语义的类型转发。
pub type PreviewFrame = @run.PreviewFrame

///|
pub type SemanticHitNode = @run.SemanticHitNode

///|
pub type SemanticPatchRequest = @run.SemanticPatchRequest

///|
pub(all) enum PreviewMode {
  PmFrame
  PmWeb
}

///|
/// 预览渲染档位（S5i 后落在运行域 UI 切片的 web_preview 布尔上）：壳内视图
/// 与服务层仍按枚举读，这里做布尔→档位的边界换转。
pub fn Model::preview_mode(model : Model) -> PreviewMode {
  if model.run_ui.web_preview {
    PmWeb
  } else {
    PmFrame
  }
}

///|
/// 组合 profile（M7）：完整版（默认）/ 教学版（只保留图形化模式——
/// 无终端、无工程、会话精简；这是「无特权内核」的验收证明：教学版 =
/// 组合根少注册能力与模式，产品功能自洽地缺席而非崩溃）。
pub(all) enum StudioProfile {
  Full
  Teaching
} derive(Eq)

///|
pub extend StudioProfile with Eq::{not_equal, equal}

///|
/// 左栏视图：程序结构树 / 本地数据 / 工程资源管理器 / AI 会话列表 / 收起。
pub(all) enum LeftView {
  LeftTree
  LeftData
  LeftProject
  /// AI 会话列表（M3，AI 模式的预设左栏）
  LeftAiSessions
  LeftHidden
}

///|
/// 右栏 Context 页签：属性 / 状态 / 数据 / 动作 / 依赖 / 运行时。
pub(all) enum ContextTab {
  CtxProps
  CtxState
  CtxData
  CtxActions
  CtxDeps
  CtxRuntime
}

///|
/// 底栏页签：运行审计 / Console / 问题（诊断汇总）/ 工作区搜索 / 真终端。
/// 原来是 `bottom_audit : Bool` 两态开关，问题面板加入后升级为枚举。
///
/// **这里只有只读面板**。AI 输入面曾经是一条 `BtAi` 页签（与右栏停靠档二选一，
/// 还要一对互为出口的切换钮）；宿主唯一化后它只有一个家 = 右栏底部的钉底
/// composer（见 `ide_right_panel`），这条页签随之取消。
pub(all) enum BottomTab {
  BtAudit
  BtConsole
  BtProblems
  /// 工作区全文搜索（G4 F3）
  BtSearch
  /// 真终端（M5，AI 模式专属页签）
  BtTerminal
}

///|
/// 树上的「非控件」选中目标：窗体 / 变量 / 数据文件。
///
/// 为什么单列一个类型：`selected_control` 与 `selected_handler` 是两条
/// 正交的字符串槽（控件用名字、子程序用 `控件@事件`），但窗体、变量、
/// 数据文件**没有可寻址的控件实体**——硬塞进 `selected_control` 会让
/// `find_selected_control` 查不到（右栏退化成「什么都没选」），还与控件名
/// 有撞名风险。用一个显式枚举表达「选中的是哪一个非控件对象」。
///
/// **互斥纪律**：任一时刻只有一条槽有效，所有入口经 `select_target` 与
/// `select_control_by_name` 单一漏斗（见 `update_selection.mbt`）。此前
/// `SelectHandler` 忘了清 `selected_control`，于是「点了子程序、右栏还显示
/// 上一个控件的属性」——正是缺少漏斗的直接后果。
pub(all) enum SideTarget {
  /// 窗体本身（标题 / 设计尺寸）。
  SideWindow
  /// 程序变量（名称 / 初值）。
  SideVariable(String)
  /// 本地数据条目（列表/表格控件的行，或变量集合）。
  SideData(String)
  /// **自定义积木**（Scratch 的「我的积木」）：名称 / 参数 / 函数体。
  /// 选中它之后右栏显示函数名，积木画布进入该函数的体（`current_handler`
  /// 的对称概念——`current_func`）。
  SideFunction(String)
}

///|
/// 输入条模式（设计稿 `#modeSeg`：修改 / 生成 / 解释 / 修复）。
/// 设计稿里它只是个高亮切换，没有行为；这里给它真语义——决定「发送」
/// 走哪条既有通道，所以四个模式都不引入新的执行路径：
/// - 修改/生成 → GenerateProposal（生成是「以空程序为基」的修改）
/// - 解释      → ExplainHandler（本地确定性讲解，native 可走真实模型）
/// - 修复      → RestoreCodeDraft（把代码草稿重置回 IR 的规范渲染）
/// 类型本体随 S4b AI 视图迁入 plugins/ai/ai_state.mbt（含 Eq）；app 保留别名。
pub type ComposerMode = @ai.ComposerMode

///|
/// 任务模式（M2 三模式工作台）：活动栏唯一职责——「我在哪个任务里」。
/// 每个模式绑定一套全区域预设（左栏/中心/右栏/底栏页签，见计划的预设表），
/// 切换 = 一次性应用预设；模式内的临时收放不回写预设（契约 3）。
pub(all) enum StudioPerspective {
  /// 图形化编辑：左栏结构树 / 中心可视化（画布/预览胶囊）/ 右栏检查器 /
  /// 底栏 审计│Console│问题│AI 输入
  PsVisual
  /// 代码编辑：左栏工程文件树 / 中心代码编辑器 / 右栏 AI 停靠卡（VS Code 口径）/
  /// 底栏 审计│Console│问题
  PsCode
  /// AI 工作台：左栏会话列表(M3) / 中心全幅会话流 / 右栏默认不显示 /
  /// 底栏 真终端(M5)
  PsAi
  /// 设计工作台（ 目标模式 M5）：全幅设计画布（易语言式拖拽）
  /// + 右栏检查器；不出现程序结构树与实时应用预览列。
  PsDesign
  /// 积木工作台（同上）：全幅积木画布（分类面板/自由画布）+ 右栏 AI
  /// 助手；不出现程序结构树与实时应用预览列。
  PsBlocks
} derive(Eq)

///|
pub extend StudioPerspective with Eq::{not_equal, equal}

///|
/// AI 工作区面板（RvWorkspace）的页签：更改（提案历史）/ 文件（工程树）。

///|
/// 右栏 AI 工作区页签（S4d 状态切片移 plugins/ai）。
pub type RightPanelTab = @ai.RightPanelTab

///|
/// 右栏当前视图：取代旧 `right_visible`（布尔）与 `ai_anchor` 的 AiDocked 档
/// 的 2×2 组合——单一枚举消除两状态互拉（历史上出过「收起底栏 AI 自己跑
/// 去右栏」的事故，根因就是两个独立状态描述同一件事）。
///
/// **三页 + 收起（VS Code 侧栏口径）**：右栏是一条**分页**的面板，页由面板头
/// 的页块切换器选。旧版把检查器与 AI 输入面塞在同一页（输入面钉在检查器
/// 底部），那是「一个宿主」时代的折中；分页后各归其位：
///
/// - `RvContext` = 检查器页：六个子页签 + 对象条 + 快速操作 + 运行时监视。
///   **不含输入面**——检查器不该为聊天让出常驻高度。
/// - `RvAi` = AI 页：会话转录（滚动）+ 底部圆角输入卡 + 状态行。会话管理与
///   输入面都在这一页，对应 VS Code 侧栏的「聊天」页。
/// - `RvWorkspace` = AI 工作台模式（`PsAi`）右栏：更改/文件双页签。这是
///   **另一个产品面**（审阅 agent 改动），不属侧栏分页体系，故独立成档。
/// - `RvHidden` = 右栏不占宽。
pub(all) enum RightView {
  /// 检查器页：六个子页签 + 对象条 + 快速操作 + 运行时监视
  RvContext
  /// AI 页：会话转录 + 底部输入卡（VS Code 侧栏「聊天」页）
  RvAi
  /// AI 工作台模式的右栏：更改（提案历史）/ 文件（工程树）双页签
  RvWorkspace
  /// 右栏不占宽
  RvHidden
} derive(Eq)

///|
pub extend RightView with Eq::{not_equal, equal}

///|
/// AI 卡与提案历史的类型定义已迁入 AI 插件包（M3 会话切片化：
/// `plugins/ai/ai_state.mbt`）；app 保留公开别名，既有引用零改动。
pub type AiCardKind = @ai.AiCardKind

///|
pub type AiCard = @ai.AiCard

///|
/// 运行审计条目种类：通过 / 运行 / 副作用待确认 / 错误。
pub(all) enum AuditKind {
  AuditOk
  AuditRun
  AuditWarn
  AuditError
}

///|
/// 运行审计条目：时间线上的一条事实（编译/启动/绑定/副作用/错误）。
/// 副作用卡（AuditWarn）是**告知 + 跳转**，不是第二条外发通道——
/// `提交数据` 的真实闸门仍在指令机里（AnswerGate）。
pub(all) struct AuditEntry {
  kind : AuditKind
  // 会话内递增序号（时间戳在视图层生成，模型不读时钟）
  seq : Int32
  text : String
  // 副作用卡的补充描述（将写什么、目标当前几行）
  detail : String
  // 错误卡的调用栈文本
  stack : String
  // 是否已处理（确认/拒绝/已修复）：已处理条目降透明度
  settled : Bool
  settled_note : String
}

///|
/// Console 日志级别：INFO / WARN / ERROR。
pub(all) enum LogLevel {
  LogInfo
  LogWarn
  LogError
}

///|
/// Console 日志行：编译/运行/Agent 的原始痕迹（设计稿 consolePane）。
pub(all) struct LogLine {
  level : LogLevel
  // 会话内递增序号：稳定 key + 追加顺序
  seq : Int32
  text : String
}

///|
/// 被监视的运行时值：变量名 + 文本值 + 类型标签。
pub(all) struct WatchRow {
  name : String
  value : String
  type_label : String
}

///|
/// 积木画布分类条的一项：分类 + 该分类在画布中的首个块下标
/// （-1 = 当前子程序没有该分类的块，视图层灰显）。
pub(all) struct BlockCategoryEntry {
  category : @blocks.BlockCategory
  first_index : Int32
}

///|
/// 本地数据文件（设计稿「本地数据」视图）：程序外挂数据面的只读投影。
/// 当前 IR 没有真实文件系统——条目由程序里的列表/表格控件与变量推导，
/// 让「数据从哪来」在界面上有落点，而不是假装有文件 IO。
pub(all) struct DataFileEntry {
  name : String
  meta : String
  locked : Bool
  // 预览文本（等宽展示，逐行）
  preview : String
}

///|
/// 代码编辑器的一行：行号 + 高亮 token 序列。
pub(all) struct CodeLine {
  number : Int32
  tokens : Array[CodeToken]
}

///|
/// 高亮 token 种类（渲染层取色，模型只带语义分类）。
pub(all) enum CodeTokenKind {
  TokKeyword
  TokString
  TokNumber
  TokBuiltin
  TokComment
  TokPlain
}

///|
/// 高亮 token：种类 + 原文。
pub(all) struct CodeToken {
  kind : CodeTokenKind
  text : String
}

///|
/// 带源内偏移的高亮 token：`start` 是全文绝对偏移（编辑器 run 的
/// `source_range` 需要全文坐标，行内坐标会在换行处错位）。
pub(all) struct RangedToken {
  start : Int32
  text : String
  kind : CodeTokenKind
}

///|
/// IR 语句 → 代码行的映射区段：语句路径 + 行区间（1 起的闭区间）。
/// 由「顺序渲染每条语句并取行区间」推导——不把行号写进 IR，
/// 映射是渲染的副产品（IR 仍是唯一事实来源）。
pub(all) struct IrLineSpan {
  path : Array[Int32]
  kind : @blocks.BlockKind
  depth : Int32
  first_line : Int32
  last_line : Int32
}

///|
/// 命令面板命令：id + 本地化标签 + 分组 + 快捷键提示 + 选中后发出的消息。
/// 设计稿的命令面包含「确认全部副作用 / 锚点循环 / 停靠 / 药丸 / 折叠底栏 /
/// 打开设置」等 Studio 自有命令，比 moui 文本命令协议的 10 个 id 更宽，
/// 所以这里用 Studio 自己的表（原 @core.ActionCommand 列表保留为视图控件
/// 的输入，两者共用 command_message 之外的独立映射）。
pub(all) struct StudioCommand {
  id : String
  label : String
  group : String
  hint : String
}

///|
/// 代码视图外观（M5-5e）：中英 DSL 降级为显示外观，MoonBit 是默认显示——
/// IR 仍是唯一事实来源，两种外观都是 IR 的可再推导投影。
pub(all) enum CodeAppearance {
  AppMoonBit // MoonBit 子集源码（codegen 产物形状，代码真源的显示）
  AppDsl // 中英 DSL（教学显示外观；沿用 parse_handler_body 编辑提交）
}

///|
pub(all) struct Model {
  program : @ir.StudioProgram
  language : UiLanguage
  code_appearance : CodeAppearance
  /// 跨域事件出口（M1 插件化）：update 在事实发生处推进（见 app/events.mbt），
  /// 程序包装层每趟排空一次并经 kernel 事件总线翻译成后续消息。取代旧的
  /// pending_code_project / pending_build / build_seq 三个跨域 flag。
  // 新建工程进行中的草稿（folder projects）：非空 = 选目录/落盘流进行中。
  new_project : NewProjectDraft?
  // 新建工程的一次性放行标记（CkNewProject 确认续行；语义同 open_confirmed）
  new_project_confirmed : Bool
  // 当前程序所属工程根（"" = 无所属——出厂样例/未恢复工程）。决定激活
  // 工程时要不要读 IR 快照恢复（同 root 不重读）。
  program_root : String
  outbox : Array[StudioEvent]
  /// 迁移写盘目录（M6③）：打开 .studio.json 时 = 旧文件所在目录；
  /// 由代码工程写盘事件的发出点消费（`emit_code_project_write`）。
  pending_open_dir : String?
  /// 预览模式一的画布/布局二分（M4 收尾）：true = 布局设计器画布。
  preview_design_open : Bool
  mode : Mode
  // 设计画布缩放：0 = 适应窗口（画布等比铺满画布列，默认行为）；
  // >0 = 固定比例（画布逻辑尺寸 640×zoom，超出视口由滚动接管）。
  design_zoom : Double
  selected_control : String
  selected_handler : String
  /// 非控件选中（窗体 / 变量 / 数据文件）。`None` = 选中落在控件或子程序上。
  /// 三条槽互斥，由 `select_target` / `select_control_by_name` 单一漏斗保证。
  side_target : SideTarget?
  code_draft : String
  code_error : String
  // 代码编辑器（richtext 受控面）的光标/选区/滚动与补全弹层（候选词/开关）
  // 已在 S5g 并入 plugins/code 的 CodeUiState 切片（单一 code_ui 字段）。
  // 当前草稿的实时语法诊断（编辑即校验；提交/切换时重算）仍是跨域读数，住壳。
  code_diagnostics : Array[@code_editor.CodeDiagnostic]
  code_ui : @code.CodeUiState
  // 破坏性操作待确认卡（None = 无）。见 confirm.mbt 的纪律说明。
  pending_confirm : ConfirmKind?
  // 「打开项目」覆盖确认后的一次性放行标记（确认 → Effect 重投时绕过
  // dirty 守卫；OpenRequested 放行即复位）。
  open_confirmed : Bool
  // 运行时检查器：最近一次快照（入口注入的格式化文本）+ 摘要历史 +
  // 「回调不可用」标记（未注入快照通道的入口，如裸测试组合根）
  runtime_report : RuntimeInspectSample?
  runtime_missing : Bool
  runtime_history : Array[String]
  // 当前运行轨：顶栏显式切换；两轨运行态各自独立保存
  run_track : RunTrack
  // 编译轨是否可达（native 入口为真；Web 端显式声明只有解释轨 + 源码预览）
  compile_track_available : Bool
  // 解释轨运行态
  run : RunModel?
  // 编译轨运行态（native 入口可达；Web 恒为 None）
  compiled_run : CompiledRun?
  // 最近一次真编译（moon check/build）报告；失败诊断回渲染到代码/运行视图
  compile_report : @export.CompileReport?
  // 真编译进行中（执行器已入队/运行）：防重复排队，视图显示加载态
  compile_busy : Bool
  // 真编译进度（每一步开始/结束各推一条）：空 = 尚未开始或已收尾。
  // 只 busy 期间有内容——完成/失败后进度条让位给报告，避免两个读数打架。
  compile_progress : Array[@export.CompileProgress]
  // 工具链原始输出展开态已迁 run_ui 切片（RunUiState.compile_output_open，S5i）。
  // 命令面板（技术风 IDE 的键盘优先入口）：显隐 + 过滤查询
  command_palette_open : Bool
  command_palette_query : String
  /// 命令面板中悬停的命令 id（"" = 无）。悬停是瞬态，与 IR 悬停同纪律。
  hover_studio_command : String
  /// 图标栏/动作簇的悬停提示（"" = 无）。图标按钮只有图形没有文字，
  /// 需要一条说明通路。采用 IDE 的成熟口径：**悬停时把说明写进状态栏**
  /// （VS Code / IDEA 都这么做），一处状态即可覆盖整簇图标，且键盘用户
  /// 同样可达。框架的 `@views.tooltip` 是可选替代（需逐元素 hover 状态）。
  hover_hint : String
  pending : PendingProposal?
  // AI 会话切片（M3 插件化）：草稿/线程卡/提案历史按会话隔离，
  // 见 plugins/ai；`pending` 提案与审计仍走全局通道（契约 4）
  ai_sessions : @ai.AiSessions
  // AI 域 UI 状态切片（S4d）：composer/provider/转录滚动/会话列表 UI/
  // 对话框开合等纯界面偏好，见 plugins/ai 的 AiUiState。
  mut ai_ui : @ai.AiUiState
  prompt_error : String
  // AI 能力可用性（组合根声明）：浏览器入口没有 HTTP 通道，显式降级——
  // composer 隐藏 + 引导文案，不出「点了必失败」的假按钮。
  ai_available : Bool
  // 未保存标记：程序编码 ≠ 最近一次保存/打开/还原基线时为真，标题旁显示 ●
  dirty : Bool
  saved_encoding : String
  draft_encoding : String
  notice : String
  // 导出独立应用是否可达：native 有系统目录选择 + 写盘（NSOpenPanel）；
  // Web 的目录「选择」返回的是文件名列表而非可写路径，写盘必然失败——
  // 与 compile_track_available 同一口径：不可达就显式声明，不假装能导。
  export_available : Bool
  // 导出 bundle 剩余未落盘的文件数（>0 = 导出进行中；归零时才报「已导出」，
  // 否则 25 个文件各回一条完成消息，会把过程误报成 25 次成功）。
  export_pending : Int32
  explanation : String
  // AI 请求进行中（真实 provider 生成/讲解）：面板显示加载态
  ai_busy : Bool
  // 积木视图编辑态：选中块（block_chain 下标，-1 = 无）与语句草稿
  selected_block : Int32
  block_draft : String
  // 积木域 UI 状态切片（S5e）：语句面板开合/分类、画布滚动、值编辑草稿、
  // 拖放骨架、右键菜单锚点，见 plugins/blocks 的 BlocksUiState。
  // 打开值编辑/提交/落拖/画布手势等需读 program 几何或提交 IR 的臂仍住壳，
  // 经组合根直接读写本切片嵌套字段（与 ai_ui 同形态）。
  mut blocks_ui : @blk.BlocksUiState
  // `询问` 闸门的回答草稿（用户正在输入的内容）。
  gate_answer_draft : String
  // 悬停中的 IR 路径（None = 没有悬停）。绘制时与 `ir_highlight` 取并集。
  hover_path : Array[Int32]?
  // 设计画布拖拽态：按下命中控件时建立，松开清除
  drag : DragState?
  // 运行期活状态：跨事件累积的变量值与控件文本（易语言式全局量）
  runtime_values : Map[String, @studio_lang.Value]
  runtime_texts : Map[String, String]
  runtime_rows : Map[String, Array[String]]
  runtime_selections : Map[String, Int32]
  // 解释轨随机种子：每次事件推进一格后交给新的 RunState。
  // **必须跨事件保留**——每次事件都从同一个种子起算的话，同一个按钮点
  // 十次会得到十个相同的「随机」结果（点名册每次都是「王五」），用户读到
  // 的现象就是「运行之后点按钮没反应」。编译轨的种子在 Runtime.rng 里。
  runtime_seed : Int32
  // 虚拟时钟（切片 G）：只在运行期间步进（TimerTick 每秒一次），
  // 累计到窗体 timer_interval 秒即触发一次 @定时器 处理器
  timer_elapsed : Int32
  // 撤销/重做：变更前快照栈（深度 UNDO_DEPTH）与重做栈
  undo_stack : Array[UndoEntry]
  redo_stack : Array[UndoEntry]
  // 积木画布拖拽（同层重排）进行中
  block_drag : BlocksDragState?
  // === v4 IDE 壳工作区状态（全部会话内，不持久化）===
  // 中心工作区：可视化 / 代码 / 空舞台
  workspace : WorkSpace
  // 编辑工作台：文档、编辑器布局与窗格编排。壳只负责模式/工作区策略。
  workbench : @wb.WorkbenchState
  // 左栏视图（图标栏切换；收起时不占宽度）
  left_view : LeftView
  // 左/右栏宽度（列间 sash 拖拽改宽；默认 = LEFTBAR/@chrome.RIGHTBAR_WIDTH，
  // `shell_chrome_widths` 按它们分配三列，中心列吃剩余）
  left_width : Double
  right_width : Double
  // 任务模式（M2 三模式工作台）：活动栏唯一职责，切换 = 应用预设
  perspective : StudioPerspective
  // 组合 profile（M7）：Teaching = 只开放图形化模式 + 无终端
  profile : StudioProfile
  // 右栏当前视图（M2）：取代 right_visible × ai_anchor 的 2×2 组合。
  // 分页后它同时决定**正文画哪一页**与**输入面在不在场**（只有 RvAi 与
  // PsAi 中心有输入面）——单一状态，不再需要「输入面在哪」的独立推导。
  right_view : RightView
  // 沉浸式无边框：true 时顶栏之上多一条窗控条（信号点 + 拖拽区）。
  // 平台入口按自己有没有无边框窗口决定——Web 恒 false。
  immersive : Bool
  // （左栏结构树搜索查询 / 展开分组集合已并入 project_state 切片，见下）
  // 工程域状态切片(S2b-1,ADR 0038/0039):资源管理器与
  // 工程 tab 的全部状态住在 plugins/project 的 ProjectState。
  project_state : @proj.ProjectState
  // 工程记录恢复中（G2 W3）：>0 = 还有 N 个 boot 重扫未回来（静默合并）;
  // 0 = 常规导入语义（带通知与预览 harness）。restore_active_root 是本次
  // 恢复要重新选中的工程根（全部重扫回来时落位）。
  projects_restore_pending : Int32
  restore_active_root : String
  // G7.3 插件管理:禁用清单（静态装配的「启用/禁用」诚实形态——禁用 =
  // 组合根装配时过滤贡献项入口,不是运行时卸载）。id: ai / terminal / markdown
  plugin_disabled : Array[String]
  // G7.2 P3e 画布交互:复制剪贴板(会话内) + 多选模式与成员集
  control_clipboard : @ir.Control?
  multi_select_mode : Bool
  multi_selected : Array[String]
  // G7.4 外观:true = 暗色(默认);settings 持久化 "1"/"0"
  ui_dark : Bool
  // G7.4 解释轨断点:当前 handler 的源码行号集合;RunStart/换 handler 清空
  breakpoints : Array[Int32]
  // G4 全文搜索:命中集 + 进行中标记（查询草稿已并入 project_state.search_query，
  // 运行与回执在服务层；结果面板挂 BtSearch 页签）。
  search_hits : Array[SearchHit]
  search_busy : Bool
  // 构建服务(M0-7):最近一次构建报告(诊断汇进 Problems)与进行中标记。
  // 待执行请求已改事件驱动(M1):过门即发 EvBuildSubmit,不再存 pending_build。
  last_build : @build.BuildReport?
  build_busy : Bool
  // 预览 harness 落盘(M1):导入成功后逐文件写 .studio/preview(Export
  // 三段式同款——队列在 Model,回执推进游标),写完置 None
  preview_write : PreviewWriteState?
  // 预览帧(M1-2):FramePreview 构建回执解析出的可重放帧
  preview_frame : PreviewFrame?
  // 语义点选(M1-3):选中的语义节点下标(帧快照内稳定)+ label 编辑草稿
  selected_semantic : Int32?
  semantic_draft : String
  // 表单设计器会话(M4-2):form.mbt 加载/编辑/保存
  form_designer : FormDesignerSession?
  selected_form_control : Int32?
  // 预览模式条（画布快览 / web 实时）+ 编译输出展开态已并入运行域 UI 切片
  //（@run.RunUiState，S5i）；web 预览 URL/打开标记由服务层驱动，仍住壳。
  run_ui : @run.RunUiState
  preview_web_url : String?
  preview_web_opened : Bool
  // 右栏 Context 页签
  ctx_tab : ContextTab
  // 底部横条展开态与高度（审计 + Console）
  bottom_open : Bool
  bottom_height : Double
  // 底部横条当前页签：审计 / Console / 问题
  bottom_tab : BottomTab
  // 运行审计时间线（会话内）
  audit_entries : Array[AuditEntry]
  audit_seq : Int32
  // Console 日志（会话内）
  log_lines : Array[LogLine]
  log_seq : Int32
  // 最近修改（会话内，最多保留 RECENT_LIMIT 条）
  recent_changes : Array[RecentChange]
  recent_seq : Int32
  // （积木上下文菜单/拖放骨架/画布滚动均已并入 blocks_ui 切片，见上）
  // 流式生成进行中（M4）：StreamChunk 分片只在为真时追加（停止即截断）
  ai_streaming : Bool
  // 墙钟快照（对白转录）：组合根注入 wall_clock 闭包时每秒经 ClockUpdated
  // 刷新；默认常数钟（clock.mbt）——时间戳/时长/相对时间的唯一来源
  clock : StudioClock
  // 终端插件状态切片（M5）：全模式底栏可用（M8）；web = unavailable 空态
  terminal : @terminal.TerminalState
  /// 终端页签开合（M8）：开 = 页签可选、选中显示交互终端；关 = 已 kill、
  /// 再点页签重开（重派生）。关闭动作 = 再点选中的终端页签。
  mut terminal_open : Bool
  /// 终端屏滚动（M8 用户反馈②）：受控 offset（跟随用户手动滚动）+
  /// 请求序号（新输出时自增 → 强制滚到底部，scroll 容器 clamp）
  mut terminal_scroll : @geometry.Point
  mut terminal_scroll_seq : Int32
  // toast：文本 + 是否警告（会话内，最多 TOAST_LIMIT 条）
  toasts : Array[ToastEntry]
  // （积木分类条选中分类 / 语句插入面板开合已并入 blocks_ui 切片，见上）
  // （结构树「新建」菜单分组已并入 project_state.tree_create_group）
  // IR↔代码行映射高亮：当前高亮的语句路径（空 = 无）
  ir_highlight : Array[Int32]
}

///|
pub(all) enum Msg {
  ProjectOp(@proj.ProjectMsg) // 工程域子消息委托(S2b-2,Feature::scope)
  Noop // 设计舞台展示态控件的兜底回调（输入被手势覆盖层拦截，正常不触发）
  SwitchLanguage
  CycleCodeAppearance // 代码视图外观切换：MoonBit（默认显示）⇄ 中英 DSL（M5-5e）
  SetCodeAppearance(CodeAppearance) // 直达目标外观（双芯片入口，实测反馈）
  ProjectFileLoaded(String, @services.ServiceTaskResult[String]) // 工程文件读取回执（挂载/刷新 workbench 文档）
  SaveProjectFile // 保存活动文件文档（写盘）
  SaveAllFiles // 保存全部脏文件文档（G4 多标签）
  ProjectFileSaveFinished(String, @services.ServiceTaskResult[Unit]) // 保存回执（rel 定位文档）
  // 文档切换/编辑/关闭已迁 workbench（WorkbenchOp）；脏文档关闭经确认流放行。
  // === 文件 CRUD（G4）：新建 / 重命名（inline 输入 + 服务链）===
  // 新建 = write_text → 回执开 tab + 重扫;改名 = read→write→delete 三步链,
  // 每步回执驱动,失败结构化提示已到哪步（半完成不静默）。
  // 草稿/开合/取消（FileCreateDraft/Dismiss、FileRenameStart/Draft/Dismiss）
  // 已并入 project_state 切片；提交（*Commit）与回执仍住壳（写盘服务链）。
  FileCreateCommit
  FileRenameCommit
  ProjectFileCreated(String, @services.ServiceTaskResult[Unit])
  ProjectRenameRead(String, String, @services.ServiceTaskResult[String])
  ProjectRenameWritten(String, String, @services.ServiceTaskResult[Unit])
  ProjectRenameDeleted(String, String, @services.ServiceTaskResult[Unit])
  // === 全文搜索（G4 F3）：草稿 → 运行（服务链扫工程树）→ 命中集 → 跳转 ===
  TogglePlugin(String)
  PluginsLoaded(@services.ServiceTaskResult[String?])
  // 属性 v2（G7.2）：文本属性与布尔属性两条编辑通道
  SetControlPropText(String, String, String)
  ToggleControlProp(String, String)
  // 画布交互(G7.2 P3e):复制/粘贴/置顶置底/键盘微调/多选模式
  CopySelectedControl
  PasteControl
  BringToFront(String)
  SendToBack(String)
  NudgeControl(String, Int32, Int32)
  ToggleMultiSelectMode
  ToggleUiDark
  UiDarkLoaded(@services.ServiceTaskResult[String?])
  ToggleBreakpoint(Int32)
  RunToBreakpoint
  // 全文搜索查询草稿（SearchQueryDraft）已并入 project_state 切片；
  // 运行 / 回执 / 命中跳转（SearchRun/SearchFinished/SearchHitClicked）住壳。
  SearchRun
  SearchFinished(@services.ServiceTaskResult[Array[SearchHit]])
  SearchHitClicked(String)
  CodeProjectSaved(@services.ServiceTaskResult[Unit]) // 代码工程骨架落盘回执（M6①）
  SetMode(Mode)
  SetDesignZoom(Double)
  SelectControl(String)
  /// 选中一个**非控件**对象（窗体 / 变量 / 数据文件）——左栏结构树中
  /// 这三类行此前没有 `on_tap`，点了完全没反应。
  SelectSide(SideTarget)
  /// 修改窗体标题（右栏窗体属性）。运行舞台的拟真标题条与导出应用的
  /// 窗口标题都读它。
  SetWindowTitle(String)
  SetTimerInterval(String)
  // 分组头「新建」菜单开合（ToggleTreeCreate）已并入 project_state 切片。
  /// 新建一个程序变量（分组头「变量 +」）。名称自动去重（`变量1`、`变量2`…），
  /// 初值取空串——与 `Declare` 语句的空文本初值同一口径。
  AddVariable
  /// 重命名变量（右栏属性）。所有引用该变量的表达式同步改名。
  RenameVariable(String, String)
  /// 修改变量初值（右栏属性）。
  SetVariableInit(String, String)
  /// 删除变量（右栏属性）。引用它的语句**不**自动清理（那会静默改写程序
  /// 语义）——由 `validate_program` 在编译/导出时如实报未声明变量。
  DeleteVariable(String)
  /// 清空选中（控件与事件子程序一起）。设计稿右栏 Context 的 `#clearSel`：
  /// 不给出这个出口的话，选中只能被**另一个选中**覆盖——用户没法回到
  /// 「什么都没选」的中性态，右栏会一直显示上一个对象的属性。
  ClearSelection
  CanvasPress(Double, Double)
  CanvasTap(Double, Double)
  CanvasDragTo(Double, Double)
  CanvasRelease(Double, Double)
  SetControlText(String, String)
  SetControlName(String, String)
  SetControlItems(String, String)
  SetControlRect(String, @ir.RectField, String)
  AddControl(@ir.ControlKind)
  DuplicateControl(String)
  DeleteControl(String)
  SelectHandler(String)
  CreateHandler(String, @ir.EventKind)
  EditCode(String)
  // 编辑器光标/选区/滚动/补全弹层开合（EditorCaretMoved/EditorScrolled/
  // DismissCompletion）已并入 plugins/code 的 CodeUiState 切片（CodeUiOp）。
  // 运行时检查器：按需采样（打开页签 / 点击刷新）
  RuntimeRefresh
  // 代码情报：触发/应用补全/跳到声明需读 code_draft/program 计算，仍住壳；
  // 候选回写与弹层开合走 CodeUiOp。
  TriggerCompletion
  ApplyCompletion(String)
  JumpToDeclaration
  CodeUiOp(@code.CodeUiMsg)
  // 破坏性操作确认流：请求 / 接受（续行原消息）/ 取消
  RequestConfirm(ConfirmKind)
  ConfirmAccepted
  ConfirmDismissed
  Undo
  Redo
  // composer 输入草稿（SetPrompt）已并入 AiSessionOp(SetPromptDraft)（S5h）。
  // composer 模式/下拉、右栏工作区页签已迁 AiUiOp（S4d 状态切片）
  ComposerRun
  RealGenerationFinished(Result[String, String])
  /// 纯聊天回复回执（G1）：成功 = markdown 文本,失败 = 错误卡
  ChatSubmit
  RealChatFinished(Result[String, String])
  ExplainHandler
  RealExplanationFinished(Result[String, String])
  LanguageLoaded(String)
  EditBlock(String)
  CommitBlock
  DuplicateBlock
  DeleteBlock
  /// 键盘在积木链里上下移动选中（Scratch/IDE 口径：↑/↓ 走上/下一块）。
  /// 参数是步长（+1 / -1）。没有选中时从链首开始（+1）或链尾（-1）。
  SelectBlockStep(Int32)
  // 打开/关闭语句插入面板（ToggleStatementPalette）已并入 blocks_ui 切片
  // （BlocksUiOp）；面板开合/分类是纯 UI，插入语句（InsertStatement）仍住壳。
  /// 插入一条语句骨架：参数是分类下标与分类内模板下标。
  InsertStatement(Int32, Int32)
  /// 插入一条**自定义函数调用**（自制积木组）：参数是 `program.functions`
  /// 的下标。与 `InsertStatement` 共用 `insert_statement_at` 的校验与手术，
  /// 只是骨架文本由「模板表」换成「函数名 + 占位实参」。
  InsertCustomFunction(Int32)
  /// 从调色板**开始拖**一条骨架（Scratch 的字面手势）。
  // 调色板拖放的「开始拖骨架」（PaletteDragStart / PaletteExprDragStart）
  // 已并入 blocks_ui 切片的 BlocksUiOp；落拖的 Drop* 仍住壳（提交 IR）。
  /// 调色板拖动中回报**视口坐标**指针。
  ///
  /// 为什么是视口坐标而不是链坐标：拖拽手势被发起它的调色板行捕获
  /// （runtime 的捕获语义），画布的手势收不到移动事件——只有调色板行
  /// 看得到指针。行不知道画布的帧；视口 → 链的换算需要画布的**布局帧**
  /// （经组合根注入的 `canvas_frame` 锚点回调取，键 = "blocks-canvas"），
  /// 只有 update 侧拿得到，所以在 update 里换算（与绘制同一套逆映射）。
  PaletteDragPointer(@core.Point)
  /// 调色板拖拽**松手**：视口坐标 + 画布可用宽（与 PaletteDrop 的
  /// avail_width 同口径，落点计算要用同一组矩形）。update 换算成链坐标
  /// 后派发 `PaletteDrop`；指针不在画布上 = 取消（清 palette_drag）。
  PaletteDropAt(@core.Point, Double)
  /// **只运行选中的那一条语句**（Scratch 的「点积木就跑它」）。
  ///
  /// 语义边界（刻意收窄，避免造出第二套执行模型）：
  /// - 只跑**该语句本身**，不跑它下面的兄弟——Scratch 的「点击运行」跑的是
  ///   整个脚本（栈），那是 `RunStart` 已有的语义；
  /// - 控制流语句（if/循环）会连带跑它的**体内**（那是这一条语句的一部分），
  ///   但不会跑它之后的兄弟；
  /// - 是一次**有界沙箱执行**（沿用 `DEFAULT_MAX_STEPS` 与闸门），不是新的
  ///   执行通道。
  RunSingleBlock
  // 积木画布自动滚动 / 手动滚动已并入 blocks_ui 切片（BlocksUiOp）。
  /// **新建自定义积木**（Scratch 的「制作一个积木」）。
  ///
  /// 语言层 / 解释器 / 编译运行时**早就支持** `FuncDef`（`return` 关键字、
  /// `functions` 参数、`lower_user_function` 都在），但只能从 JSON 进来——
  /// 界面上没有任何创建入口，所以「定义一个自己的积木」在积木界面里**做不到**。
  /// 这条消息补的就是这个入口，走 IR 手术（与 `AddVariable` 同一纪律）。
  AddFunction
  /// **给当前编辑目标写说明**（Scratch 的「给这段脚本加注释」）。
  ///
  /// `Handler` / `FuncDef` 早就有 `note_zh` / `note_en` 字段，AI 上下文
  /// （`update_ai.mbt` 的 `handler_note`）也一直在**读**它——但界面上没有
  /// 任何**写**的入口，所以这两个字段永远是空的。这条消息补上入口。
  ///
  /// 写当前界面语言那一份，另一份留空由读取端回退（`handler_note` 已有
  /// 「本语言为空则用另一语言」的回退逻辑）。
  EditTargetNote(String)
  /// 重命名自定义积木（并同步改写所有调用点的函数名）。
  RenameFunction(String, String)
  /// 点击积木上的一个**值**（叶子段）→ 就地编辑它（Scratch 的「点值改值」）。
  ///
  /// 参数：语句链下标、该值的表达式路径、值类型提示（数字/文本/布尔）。
  /// 与 `EditBlock`（改整行草稿）分开：值编辑只动那一个叶子，
  /// 不重新解析整行——整行草稿会把用户没碰的部分也重写一遍。
  EditBlockValue(Int32, Array[Int32])
  /// `询问` 闸门的**回答输入**（Scratch 的「询问并等待」要能打字）。
  ///
  /// 此前闸门卡片只给「确认/拒绝」两个按钮，`AnswerGate(Bool)` 也只带布尔
  /// ——所以 `询问` 的回答内容**根本无从输入**，它只能当「是/否」用，而那
  /// 不是它的语义。这条消息让用户把回答打进去。
  GateAnswerInput(String)
  /// 提交闸门回答（带当前输入的文本）。
  GateAnswerSubmit
  // 值编辑的输入变化 / 取消（BlockValueInput、BlockValueCancel）已并入
  // blocks_ui 切片；打开（EditBlockValue）与提交（BlockValueCommit）住壳。
  /// 值编辑提交。
  BlockValueCommit
  /// 拖动报告块在画布上松手：**画布已解析出**目标洞（语句链下标 + 表达式
  /// 路径），这里只做落地。
  ///
  /// 为什么由画布解析而不是 update：洞的位置 = 逐段文本宽度累加，需要
  /// `TextSystem`；它只在**布局上下文**里，update 层拿不到。把解析放在
  /// 画布（与绘制同一份度量）才保证「画在哪就点在哪」。
  ExpressionDrop(Int32, Array[Int32])
  /// 从调色板**拖一个报告块（表达式）进洞**并落下。
  ///
  /// 参数：表达式模板下标、目标语句链下标、目标表达式路径。
  /// 与语句拖放分开：表达式**不能单独成为一条语句**，它只能替换某个
  /// 子表达式——所以落点语义是「换掉那个洞里的东西」而不是「插一行」。
  DropExpression(Int32, Int32, Array[Int32])
  /// 画布上松手时**完成调色板拖放**：按指针算落点容器与位置。
  PaletteDrop(Double, Double, Double)
  /// 从调色板**拖一条骨架到画布**并落下（Scratch 的字面手势）。
  ///
  /// 参数：分类下标、模板下标、落点列表路径、落点位置。与
  /// `InsertStatement` 共用 `insert_statement_at` 的校验与手术——
  /// 拖放只是「落点由指针决定」的插入，不是第二套插入语义。
  DropStatement(Int32, Int32, Array[Int32], Int32)
  GenerateProposal
  AcceptProposal
  RejectProposal
  // provider endpoint/model/key 与显隐已迁 AiUiOp（S4d 状态切片）
  DraftLoaded(@services.ServiceTaskResult[String?])
  RunStart
  RunStop
  SetRunTrack(RunTrack)
  CompileRun
  CompileRunFinished(@export.CompileReport)
  CompileRunFailed(String)
  /// 停止真编译：清报告与忙态，不切轨、不自动回退解释轨。
  CompileStopped
  CompileJump(Int32)
  // 编译输出展开开关已迁 RunUiOp(ToggleCompileOutput)（S5i 运行域切片）。
  /// worker 推来的一条编译进度（步开始/步结束）
  CompileProgress(@export.CompileProgress)
  /// 复制某条产物的绝对路径到剪贴板
  CopyArtifactPath(String)
  /// 在系统文件管理器里定位某条产物（macOS=Finder）
  RevealArtifact(String)
  /// **一键启动**某条产物（GUI 应用）：脱离 Studio 生命周期起进程
  RunArtifact(String)
  /// 旁路动作的结果回来了。`what` 标明是哪一种（复制/打开/启动）——
  /// 成功文案各不相同，共用一个消息就必须带上来源，否则三种成功
  /// 只能显示同一句话（或再拆三个消息，那是同一件事的三份拷贝）。
  ArtifactActionDone(ArtifactAction, @services.ServiceTaskResult[Unit])
  CommandPaletteOpen
  CommandPaletteClose
  CommandPaletteQuery(String)
  /// 命令面板行悬停（瞬态）：高亮当前行。与 IR 悬停同纪律——离开即还原。
  /// 面板选中直接产 `StudioCommandRun(id)`（见 command_palette.mbt），
  /// 不再需要一条中转消息。
  HoverStudioCommand(String)
  /// 图标/动作悬停提示（瞬态）：指针进入时给出说明文案，离开清空。
  /// 说明文案由视图层解析好（i18n 只在这一层做），状态栏直接显示。
  HoverHint(String)
  RunTick
  TimerTick
  // toast 老化节拍（每秒一次；有 toast 时订阅才活跃）
  ToastTick
  ControlInputDone(String)
  /// 在积木上右键（Scratch/IDE 口径的上下文菜单）。参数是点中的**链下标**
  /// 与画布内坐标（菜单锚点）。下标 -1 = 点空白处（只显示画布级动作）。
  BlocksContextMenu(Int32, Double, Double)
  // 关闭积木上下文菜单（BlocksContextMenuClose）已并入 blocks_ui 切片。
  /// 菜单动作：**先关菜单再执行动作**，一条消息搞定两件事。
  ///
  /// 为什么合成一条：`@views` 的 `on_tap` 每个视图只保留一个（后设的覆盖
  /// 先设的），所以「点行 = 关菜单 + 执行」不能靠串两次 `on_tap`——
  /// 实测只会触发最后一个。合成就没有这个歧义。
  BlocksMenuAction(Msg)
  RunStep
  RunResume
  AuditJump(Int32)
  /// 积木画布的三个指针消息都带 `avail_width`（画布可用宽）。
  ///
  /// **为什么必须带**：命中与绘制必须用**同一组矩形**。绘制侧
  /// （`blocks_canvas`）用真实画布宽算块体宽度，而命中侧此前用默认常量
  /// `block_width = 430`——窄窗格里块被夹窄到 ~370，点在「块右缘到 430」
  /// 之间的空隙仍会被判成命中（点在空白处却选中了积木）。
  /// 宽度是视口派生的量，update 层算不出来，只能由视图侧随手势带上。
  BlocksCanvasTap(Double, Double, Double)
  BlocksCanvasPress(Double, Double, Double)
  BlocksCanvasDragTo(Double, Double, Double)
  BlocksCanvasRelease
  RunToggle(String, Bool)
  AnswerGate(Bool)
  ControlClicked(String)
  ControlPicked(String, Int32)
  ControlChanged(String, String)
  /// 新建工程（folder projects）：参数 = 模板下标（-1 = 空白程序）。
  /// 链条：NewProjectRequested（脏程序确认后选目录）→ NewProjectRootPicked
  /// （目录确定：算骨架文件集）→ NewProjectQueueResult × N（写盘队列游标推进；
  /// 中断翻到删除相回滚）→ 完成态注册工程 + 装载模板程序 + IR 快照落盘。
  NewProjectRequested(Int32)
  NewProjectRootPicked(@services.ServiceTaskResult[String])
  NewProjectQueueResult(@services.ServiceTaskResult[Unit])
  /// 工程程序快照回执（SetActiveProject 恢复流）：读 `<root>/.studio/program.json`。
  ProjectProgramLoaded(@services.ServiceTaskResult[String])
  /// IR 快照落盘回执（EvProgramSnapshotWrite 翻译而来；失败才说话）。
  SnapshotWriteSaved(@services.ServiceTaskResult[Unit])
  SaveRequested
  SavePathPicked(@services.ServiceTaskResult[String])
  SaveCompleted(@services.ServiceTaskResult[Unit])
  OpenRequested
  OpenPathPicked(@services.ServiceTaskResult[String])
  OpenReadCompleted(@services.ServiceTaskResult[String])
  // === 工程工作台消息（M0）：导入 MoonBit 工程 ===
  // 链条：ImportProjectRequested（选目录）→ ProjectRootPicked（目录确定，
  // 走扫描任务）→ ProjectScanCompleted（扫描完：单模块或 moon.work 工作区）。
  ImportProjectRequested
  ProjectRootPicked(@services.ServiceTaskResult[String])
  ProjectScanCompleted(
    @services.ServiceTaskResult[Result[@project.ProjectScanOutput, String]]
  )
  // 扫描进度（节流回调）：资源管理器头部一行读数（G2）
  ProjectScanProgress(@project.WalkProgress)
  // 工程记录存储（G2 W3）：boot 读取回执 → 解码 → 逐 root 静默重扫；
  // 重扫回执走静默合并（不弹通知、不产 harness）；写盘请求/回执与
  // ai-sessions 同款纪律。
  ProjectsStoreLoaded(@services.ServiceTaskResult[String])
  ProjectRestoreScanCompleted(
    @services.ServiceTaskResult[Result[@project.ProjectScanOutput, String]]
  )
  ProjectsStoreWriteRequested
  ProjectsStoreSaved(@services.ServiceTaskResult[Unit])
  // 资源管理器导航(纯状态):选中工程 / 折叠目录 / 选中文件 / 会话内移除工程
  SelectProjectFile(String)
  SelectProjectFileAt(Int32, String) // 单树多根:先切活动工程再开文件
  RemoveProject(Int32)
  // VS Code 资源管理器壳(纯状态):悬停行 / 分区折叠 / 标题栏溢出菜单 /
  // inline 新建的目标目录。
  /// 标题栏 `⋯` 溢出菜单的开合（VS Code 面板头右端的省略号）。
  /// 在目录 rel 下新建文件（inline 输入）。**必须带目录**:VS Code 的
  /// 新建发生在「点的那一层」,不带目录的变体会把目标默默固定成工程根
  /// （工具栏入口与目录行悬浮 ＋ 就分不开了）。
  /// 在目录 rel 下新建文件夹（inline 输入）。与 `FileCreateAt` 同形。
  FolderCreateCommit
  // 新建文件夹(宿主直接 I/O):创建在 FolderCreateCommit 臂内联派发
  // (effect dispatch),回执走这条;没有独立的「请求」变体——有它就会是
  // 一条无人构造的死消息。
  FolderCreated(String, @services.ServiceTaskResult[Result[Unit, String]])
  // 全部折叠(= 折叠所有根目录)/ 刷新(重扫活动工程)
  ExplorerRefresh
  // 文件删除(确认后续行 + 服务回执;M0-6b)
  ProjectFileDeleteRun(String)
  ProjectFileDeleted(String, @services.ServiceTaskResult[Unit])
  // 构建服务(M0-7):UI 请求(kind)→ busy 置位 → 包装层派发注入的
  // build_submit → 回执落 last_build(诊断汇进 Problems)
  ProjectBuildRun(@build.BuildKind)
  ProjectBuildFinished(@build.BuildKind, Result[@build.BuildReport, String])
  // 预览 harness 落盘回执(成功推进游标;全部写完 = 预览就绪)
  PreviewFileWritten(@services.ServiceTaskResult[Unit])
  // 语义点选 + 字面量属性补丁(M1-3)
  SelectSemanticNode(Int32)
  SemanticLabelInput(String)
  SemanticLabelCommit
  SemanticPatchFinished(Result[String, String])
  // 表单设计器(M4-2):打开(读 form.mbt)/加载回执/拖拽结束(span 补丁+写回)
  SelectFormControl(Int32)
  SetPreviewDesignOpen(Bool)
  FormDesignOpen
  FormDesignLoaded(@services.ServiceTaskResult[String])
  FormDesignDragEnd(Int32, Double, Double)
  FormDesignResizeEnd(Int32, Double, Double)
  FormDesignSaved(@services.ServiceTaskResult[Unit])
  // 外部改动重载（M8）：手动刷新入口读 form.mbt → 比对 → 提示/重载
  FormDesignExternalCheck
  FormDesignExternalChecked(@services.ServiceTaskResult[String])
  // 预览 Frame/Web 切换 + 编译输出展开已迁 RunUiOp（运行域 UI 切片，S5i）；
  // Web 构建回执后 wrapper 派发 navigate/reload（经注入的 webview 控制器闭包）。
  RunUiOp(@run.RunUiMsg)
  PreviewNavigate(String)
  PreviewReload
  ExportRequested
  ExportDirPicked(@services.ServiceTaskResult[String])
  ExportFileWritten(@services.ServiceTaskResult[Unit])
  SetNotice(String)
  // === v4 IDE 壳消息 ===
  // 事件驱动消息（M1 内核化）：由 outbox 事件经总线翻译而来，副作用在
  // 程序包装层的臂里经服务容器执行。
  /// 代码工程骨架写盘（EvCodeProjectWrite 的翻译）：目录 + form.mbt +
  /// handlers.mbt + project_data.mbt（内嵌 IR；"" = 布局不含，跳过）
  CodeProjectWriteRequested(String, String, String, String)
  /// 程序 IR 快照写盘（EvProgramSnapshotWrite 的翻译）：绝对路径 + 编码 IR
  SnapshotWriteRequested(String, String)
  /// 构建请求派发（EvBuildSubmit 的翻译）
  BuildDispatchRequested(ProjectBuildRequest)
  /// AI 会话操作（M3 插件化）：新建/切换/删除，经 Feature::scope 委托
  /// 给 plugins/ai 的状态切片
  AiSessionOp(@ai.AiSessionMsg)
  /// AI 域纯 UI 偏好（S4d 状态切片）：composer/provider/转录滚动/会话列表
  /// 搜索悬停/对话框开合，经 Feature::scope 委托给 plugins/ai 的 AiUiState。
  AiUiOp(@ai.AiUiMsg)
  /// 终端（M5 插件）：PTY 输出增量 / 派生回执 / 关闭会话
  TerminalOutput(String)
  TerminalSpawned(Int32?)
  TerminalClose
  /// 终端直连键入（M8 交互式：键盘/文本输入经 keyboard_input 透传给 PTY；
  /// 行输入协议 TerminalInput/TerminalType 已于 2026-10-11 随 M9 收尾删除）
  TerminalWrite(String)
  /// 终端页签开关（M8）：再点选中的终端页签 = 关闭（kill + 收起）；关闭态
  /// 再点 = 重开（重派生）
  TerminalTabClose
  /// 请求宿主把键盘焦点交给终端（M8：经注入的 focus_terminal 回调调
  /// runtime.focus_key("terminal-input")——app 不接触 runtime）
  FocusTerminalRequest
  /// 流式分片到达（M4）：追加进当前会话的流式卡；已停止则忽略
  StreamChunk(String)
  /// 流式完成（正常结束）
  /// 停止生成（用户动作）：截断流式，卡片标记已停止
  StopGeneration
  /// 墙钟刷新（组合根注入 wall_clock 时 1s 一次，仅 AI 模式订阅）：
  /// 时间线 HH:MM、相对时间、「已工作 N 秒」随之走动。
  ClockUpdated(StudioClock)
  /// 复制时间线里的一条消息（参数 = 卡 seq）：走系统剪贴板。
  CopyAiMessage(Int32)
  /// 复制一条消息里的**第 index 个代码块**（块级复制）。
  ///
  /// 为什么不复用 `CopyAiMessage`：一次回复可能产多块代码，整卡复制会把
  /// 叙述文字一起拷走——用户要的是「这一块代码」。参数 = (卡 seq, 块下标)。
  CopyAiCodeBlock(Int32, Int32)
  /// 把一条用户提问回填进 composer 草稿（对白转录气泡的「编辑」）。
  EditUserPrompt(Int32)
  /// 重发一轮：把该条 AI 消息**之前的用户提问**回填草稿并立即重跑
  /// （ComposerRun 语义，不是第二条执行通道）。
  RetryUserPrompt(Int32)
  // 时间线受控滚动 / 回到底部、会话列表搜索/悬停/改名草稿 已迁 AiUiOp
  //（S4d）；改名 Start/Commit/Dismiss 因读会话或触发存储，仍住壳。
  // === 左栏会话列表（M4）===
  /// 行内改名：进入编辑态（参数 = 会话下标）
  AiSessionRenameStart(Int32)
  /// 行内改名提交（Enter）
  AiSessionRenameCommit
  // 行内改名放弃（旧 AiSessionRenameDismiss）已随 S4d 迁 AiUiOp(ClearRename)。
  /// 会话存储读取回执（M5,仅组合根配置了存储路径时发起）
  AiSessionsStoreLoaded(@services.ServiceTaskResult[String])
  /// 会话存储写盘请求（总线从 EvAiSessionsDirty 翻译而来）
  AiSessionsStoreWriteRequested
  /// 会话存储写盘回执
  AiSessionsStoreSaved(@services.ServiceTaskResult[Unit])
  // 工作区编排：图标栏切换（同一工作区再点一次 = 空舞台）
  SetWorkSpace(WorkSpace)
  // 编辑工作台的纯状态迁移（文档、窗格、分隔比）。
  WorkbenchOp(@wb.WorkbenchMsg)
  // 任务模式切换（M2）：进模式按预设置位四区域；同值再点 no-op
  SetPerspective(StudioPerspective)
  // 左栏：视图切换 / 关闭；结构树搜索 / 分组展开折叠（SetTreeQuery/
  // ToggleTreeGroup）已并入 project_state 切片。
  SetLeftView(LeftView)
  /// 显式设置右栏当前视图（M2）：关闭入口在右栏头的 ✕（只可能关 →
  /// RvHidden），重开与换视图走命令面板逃生口（studio.right.* / studio.ai.*）。
  SetRightView(RightView)
  /// 列间 sash 拖拽改宽（VS Code 口径）：指针位置 → 目标宽度在**视图层**
  /// 换算并夹取（界限依赖当帧布局），update 只再兜底夹一次。布局手势，
  /// 不产生撤销点、不标脏。
  ResizeLeftPanel(Double)
  ResizeRightPanel(Double)
  // 右栏 Context 页签
  SetContextTab(ContextTab)
  // 底栏：页签切换 / 展开折叠 / 高度拖拽
  SetBottomTab(BottomTab)
  /// 底栏高度拖拽（M8 用户反馈③）：sash 位置 → 钳制后的高度
  SetBottomHeight(Double)
  // 终端屏手动滚动旧消息 TerminalScrolled(Point) 无 update 承接（scroll_view
  // 自管手动位置，受控 offset 只由 PTY 输出的自动跟随驱动），S5i 作为死消息删除。
  // 问题面板：跳到某子程序草稿的某行（选中 handler + 光标 + 滚动对齐）
  GotoProblem(String, Int32)
  ToggleBottom
  // 审计：点击条目（跳到对应积木）/ 处理副作用卡（settled 标记）
  AuditOpen(Int32)
  AuditSettle(Int32, String)
  AuditSettleAll(String)
  // 最近修改 / Console 清空
  ClearConsole
  // AI 浮动层：药丸 / 折叠卡 / 上下文芯片（落点已由 right_view 推导，M2）
  // 沉浸式无边框窗口：三个窗控件 + 拖拽。native 映射到真实窗口请求，
  // Web/无边框未启用时是安全 no-op（不假装能关掉浏览器标签页）。
  WindowClose
  WindowMinimize
  WindowZoom
  WindowDragBy(Double)
  // AI 工作卡折叠开关已迁 AiUiOp（S4d 状态切片）
  // 快速操作：对齐左/居中/对齐右（设计稿 x=24 边距口径）
  AlignControlLeft(String)
  AlignControlCenter(String)
  AlignControlRight(String)
  // 设置 / AI 历史对话框开合已迁 AiUiOp（S4d 状态切片）
  DismissToast(Int32)
  // 命令面板 Studio 命令（比 10 个文本命令更宽的自有表）
  StudioCommandRun(String)
  // 积木域 UI 子消息委托（S5e 状态切片，Feature::scope）：语句面板开合/分类、
  // 画布滚动、值编辑草稿、拖放骨架、右键菜单等纯 UI 态。
  BlocksUiOp(@blk.BlocksUiMsg)
  // IR↔代码行映射高亮：按语句路径
  HighlightIrPath(Array[Int32])
  // 悬停联动（设计稿 `irHl`）：指针进/出代码行或积木块时高亮对应路径。
  // 与 `HighlightIrPath` 分开是因为语义不同——悬停是**瞬态**的（离开即
  // 撤销），点击是**驻留**的（再点一次才取消）。两者共用一个高亮槽位，
  // 悬停不写槽位，只在 `hover_path` 里记临时值。
  HoverIrPath(Array[Int32]?)
  // 代码草稿回归 IR 渲染（丢弃手改）——高亮区永远来自 IR 投影，
  // 草稿与 IR 分叉时由用户显式决定放弃哪边
  RestoreCodeDraft
}

///|
/// handler 定位键：控件名@事件标签（选中态在模型里用字符串携带）。
pub fn handler_key(control : String, event : String) -> String {
  "\{control}@\{event}"
}

///|
/// provider 运行时配置（来自 gitignored .config.json；缺省即空配置）。
///
/// `models` 是**模型候选清单**（composer 下拉列它）。宽松字段：缺它不报错
/// ——`load_provider_config` 对 endpoint/model/api_key 三字段是「缺一即
/// None」的严格读，若把 models 也并进去，所有现存 .config.json 都会失效。
/// 所以 models 单独 try，缺省 `[]`（= 只有当前 model 一项，今天的行为）。
pub(all) struct ProviderConfig {
  endpoint : String
  model : String
  api_key : String
  models : Array[String]
}

///|
pub fn empty_provider_config() -> ProviderConfig {
  { endpoint: "", model: "", api_key: "", models: [], }
}

///|
/// 草稿自动保存的 settings 键（编码后的程序 JSON；随会话持久化）。
pub const DRAFT_SETTINGS_KEY : String = "studio.draft"

///|
/// 外观主题 settings 键（G7.4）："1" = 暗色（默认），"0" = 亮色。
pub const UI_DARK_SETTINGS_KEY : String = "studio.ui_dark"

///|
/// 插件启用态的 settings 键（G7.3）：值为逗号连接的禁用 id 列表
/// （空串 = 全部启用）。
pub const PLUGINS_SETTINGS_KEY : String = "studio.plugins"

///|
/// 初始模型：问候样例 + 中文界面；代码草稿按当前语言播种。
/// provider_config 非空时预填面板（key 仍只进会话内存）。
pub fn initial_model(
  provider_config? : ProviderConfig,
  compile_track_available~ : Bool = false,
  export_available~ : Bool = false,
  immersive~ : Bool = false,
  pty_available~ : Bool = false,
  profile~ : StudioProfile = Full,
  ai_available~ : Bool = true,
) -> Model {
  let program = @proposals.sample_hello()
  let config = match provider_config {
    Some(value) => value
    None => empty_provider_config()
  }
  let endpoint = if config.endpoint == "" {
    "https://api.stepfun.com/step_plan/v1"
  } else {
    config.endpoint
  }
  let model_name = if config.model == "" {
    "step-5-preview"
  } else {
    config.model
  }
  let encoding = @codec.encode_program(program)
  let initial_audit = boot_audit_entries(program)
  let model = {
    program,
    language: ZhHans,
    code_appearance: AppMoonBit,
    outbox: [],
    pending_open_dir: None,
    new_project: None,
    new_project_confirmed: false,
    program_root: "",
    preview_design_open: false,
    mode: ModeDesign,
    design_zoom: 0.0,
    selected_control: "按钮",
    selected_handler: handler_key("按钮", "on_click"),
    side_target: None,
    code_draft: "",
    code_error: "",
    code_diagnostics: [],
    code_ui: @code.CodeUiState::new(),
    pending_confirm: None,
    open_confirmed: false,
    runtime_report: None,
    runtime_missing: false,
    runtime_history: [],
    run_track: Interpret,
    compile_track_available,
    run: None,
    compiled_run: None,
    compile_report: None,
    compile_busy: false,
    compile_progress: [],
    command_palette_open: false,
    command_palette_query: "",
    hover_studio_command: "",
    hover_hint: "",
    pending: None,
    ai_sessions: @ai.AiSessions::new(),
    profile,
    ai_ui: @ai.AiUiState::new(
      endpoint,
      model_name,
      config.api_key,
      config.models,
    ),
    prompt_error: "",
    ai_available,
    dirty: false,
    saved_encoding: encoding,
    draft_encoding: encoding,
    notice: "",
    export_available,
    export_pending: 0,
    explanation: "",
    ai_busy: false,
    selected_block: -1,
    hover_path: None,
    block_draft: "",
    blocks_ui: @blk.BlocksUiState::new(),
    gate_answer_draft: "",
    drag: None,
    runtime_values: @studio_lang.initial_values(program),
    runtime_texts: @studio_lang.initial_texts(program),
    runtime_rows: @studio_lang.initial_rows(program),
    runtime_selections: Map([], capacity=4),
    runtime_seed: @studio_lang.DEFAULT_SEED,
    timer_elapsed: 0,
    undo_stack: [],
    redo_stack: [],
    block_drag: None,
    workspace: WsVisual,
    workbench: @wb.WorkbenchState::new(),
    left_view: LeftTree,
    left_width: @chrome.LEFTBAR_WIDTH,
    right_width: @chrome.RIGHTBAR_WIDTH,
    perspective: PsVisual,
    right_view: RvContext,
    immersive,
    project_state: @proj.ProjectState::new(),
    projects_restore_pending: 0,
    restore_active_root: "",
    plugin_disabled: [],
    control_clipboard: None,
    multi_select_mode: false,
    multi_selected: [],
    ui_dark: true,
    breakpoints: [],
    search_hits: [],
    search_busy: false,
    last_build: None,
    build_busy: false,
    preview_write: None,
    preview_frame: None,
    selected_semantic: None,
    semantic_draft: "",
    form_designer: None,
    selected_form_control: None,
    run_ui: @run.RunUiState::new(),
    preview_web_url: None,
    preview_web_opened: false,
    ctx_tab: CtxProps,
    // 底栏默认展开且选中审计页签。**AI 输入面不在底栏**——它只有一个宿主
    // （右栏底部的钉底 composer），初始状态就可见，不需要靠底栏页签把它
    // 带到第一眼。三个只读面板与终端在同一行，一次点击可达。
    bottom_open: true,
    bottom_height: 168.0,
    bottom_tab: BtAudit,
    audit_entries: initial_audit,
    audit_seq: initial_audit.length(),
    log_lines: boot_log_lines(program),
    log_seq: 3,
    recent_changes: [],
    recent_seq: 0,
    ai_streaming: false,
    clock: default_studio_clock(),
    // 教学版 profile 强制无终端（组合根与直调 initial_model 的测试同口径）
    terminal: @terminal.TerminalState::new(
      available=pty_available && !(profile is Teaching),
    ),
    terminal_open: true,
    terminal_scroll: @geometry.Point::new(x=0.0, y=0.0),
    terminal_scroll_seq: 0,
    toasts: [],
    ir_highlight: [],
  }
  seed_code_draft(model)
}

///|
/// 启动审计：把「程序已就绪」这件事在时间线上如实说一遍（设计稿首屏三条）。
/// 内容是程序事实的派生（窗体尺寸、控件数、子程序数），不写死演示文案。
fn boot_audit_entries(program : @ir.StudioProgram) -> Array[AuditEntry] {
  let entries : Array[AuditEntry] = [
    AuditEntry::{
      kind: AuditRun,
      seq: 1,
      text: "app.audit.boot",
      detail: "",
      stack: "",
      settled: false,
      settled_note: "",
    },
    AuditEntry::{
      kind: AuditOk,
      seq: 2,
      text: "app.audit.controls",
      detail: "",
      stack: "",
      settled: false,
      settled_note: "",
    },
    AuditEntry::{
      kind: AuditOk,
      seq: 3,
      text: "app.audit.handlers",
      detail: "",
      stack: "",
      settled: false,
      settled_note: "",
    },
  ]
  ignore(program)
  entries
}

///|
/// 启动 Console：三条 INFO 说明当前会话的边界（轨、编译可达性、安全叙事）。
fn boot_log_lines(program : @ir.StudioProgram) -> Array[LogLine] {
  ignore(program)
  [
    LogLine::{ level: LogInfo, seq: 1, text: "app.log.ready", },
    LogLine::{ level: LogInfo, seq: 2, text: "app.log.track", },
    LogLine::{ level: LogWarn, seq: 3, text: "app.log.gate", },
  ]
}
