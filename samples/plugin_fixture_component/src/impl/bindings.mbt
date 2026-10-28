///|
/// Canonical ABI 导出包装（手写，对应 `wit/world.wit` 的 world）。
///
/// 导出名格式：`{package}/{interface}@{version}#{member}`——由
/// `wasm-tools component embed` 匹配到组件的 world 上。
///
/// **返回区布局**（Canonical ABI 的间接返回）：返回 i32 指针，指向一块
/// 8 字节的 retarea = [ptr(u32), len(u32)]。

///|
pub fn wasmExportDescribe() -> Int {
  let result = describe()
  let (ptr, len) = @cabi.cabi_lower_string(result)
  let return_area = @cabi.cabi_realloc(0, 0, 4, 8)
  @cabi.store32(return_area + 0, ptr)
  @cabi.store32(return_area + 4, len)
  return_area
}

///|
pub fn wasmExportDescribePostReturn(_p0 : Int) -> Unit {
  ()
}

///|
pub fn wasmExportCall(p0 : Int, p1 : Int) -> Int {
  let request = @cabi.cabi_lift_string(p0, p1)
  let result = call(request)
  let (ptr, len) = @cabi.cabi_lower_string(result)
  let return_area = @cabi.cabi_realloc(0, 0, 4, 8)
  @cabi.store32(return_area + 0, ptr)
  @cabi.store32(return_area + 4, len)
  return_area
}

///|
pub fn wasmExportCallPostReturn(_p0 : Int) -> Unit {
  ()
}

///|
// Re-export cabi_realloc for wasm linking.
pub fn cabi_realloc(
  old_ptr : Int,
  old_size : Int,
  align : Int,
  new_size : Int,
) -> Int {
  @cabi.cabi_realloc(old_ptr, old_size, align, new_size)
}
