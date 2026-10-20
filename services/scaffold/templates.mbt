///|
/// 新建/切换模板时的初始程序：下标口径与内置模板库同源（-1 = 空白程序）。

///|
/// 模板下标 → 初始程序：-1 = 空白程序，其余取内置模板库（越界回退空白）。
pub fn template_program(index : Int32) -> @ir.StudioProgram {
  let samples = @proposals.all_samples()
  if index >= 0 && index < samples.length() {
    samples[index]
  } else {
    @ir.empty_program()
  }
}
