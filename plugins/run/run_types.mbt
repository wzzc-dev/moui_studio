///|
/// 运行态：当前子程序 + 指令机状态 + 勾选框 UI 态。
/// checks 只在 app 层（运行期视觉状态，不进指令机语义）。
pub(all) struct RunModel {
  handler_label : String
  state : @studio_lang.RunState
  checks : Map[String, Bool]
  // 单步模式：为真时 RunTick 不自动推进，仅 RunStep 走一条指令
  single_step : Bool
}

///|
/// 编译轨运行态：`compiled_runtime` 的 Runtime 本身携带跨事件活状态
/// （变量/文本/行/选中/审计/闸门），因此与解释轨的 RunModel 完全独立，
/// 两轨可以各自停在各自的位置，互不干扰。
pub(all) struct CompiledRun {
  handler_label : String
  runtime : @compiled_runtime.Runtime
  checks : Map[String, Bool]
}
