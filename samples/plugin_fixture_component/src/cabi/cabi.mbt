///|
/// Canonical ABI 助手（低层线性内存操作，不依赖 GC 内部函数）。
///
/// **为什么手写**：MoonBit `wasm` target 的内联 wasm 白名单不含
/// `$moonbit.init_array8` 等 GC 内部函数，而 `wit-bindgen` 生成的胶水
/// 依赖它们。故用**纯线性内存操作**实现 bump 分配器与字符串编解码。
///
/// **字符串编码**：Canonical ABI 的 `string` 在 **MoonBit 组件**里是
/// **UTF-16LE**（MoonBit 的 `String` 内部即 UTF-16）。实测：按 UTF-8
/// 降级会被宿主当 UTF-16 解读 → 乱码（`≻潦浲瑡㨢洢畯`）。

///|
extern "wasm" fn mem_load8(ptr : Int) -> Int =
  #|(func (param i32) (result i32) (i32.load8_u (local.get 0)))

///|
extern "wasm" fn mem_store8(ptr : Int, val : Int) -> Unit =
  #|(func (param i32 i32) (i32.store8 (local.get 0) (local.get 1)))

///|
extern "wasm" fn mem_load32(ptr : Int) -> Int =
  #|(func (param i32) (result i32) (i32.load (local.get 0)))

///|
extern "wasm" fn mem_store32(ptr : Int, val : Int) -> Unit =
  #|(func (param i32 i32) (i32.store (local.get 0) (local.get 1)))

///|
extern "wasm" fn mem_size() -> Int =
  #|(func (result i32) (memory.size))

///|
extern "wasm" fn mem_grow(pages : Int) -> Int =
  #|(func (param i32) (result i32) (memory.grow (local.get 0)))

///|
let heap_base : Int = 65536

///|
let heap_offset : Ref[Int] = Ref(0)

///|
fn get_heap_offset() -> Int {
  heap_offset.val
}

///|
fn set_heap_offset(offset : Int) -> Unit {
  heap_offset.val = offset
}

///|
fn ensure_heap_init() -> Unit {
  if get_heap_offset() == 0 {
    set_heap_offset(heap_base)
  }
}

///|
/// Canonical ABI 的 realloc（宿主用它给 guest 分配内存）。
///
/// 实现成 **bump 分配器**：只向前推进，不回收——单次调用周期内分配
/// 量极小（一条 JSON 响应），够用且实现简单。
pub fn cabi_realloc(
  _old_ptr : Int,
  _old_size : Int,
  align : Int,
  new_size : Int,
) -> Int {
  ensure_heap_init()
  let offset = get_heap_offset()
  let aligned = (offset + align - 1) & -align
  let new_offset = aligned + new_size
  let pages_needed = (new_offset + 65535) / 65536
  let current_pages = mem_size()
  if pages_needed > current_pages {
    let grow_result = mem_grow(pages_needed - current_pages)
    if grow_result == -1 {
      abort("cabi_realloc: memory grow failed")
    }
  }
  set_heap_offset(new_offset)
  aligned
}

///|
/// 把字符串按 **UTF-16LE** 降级到线性内存，返回 (ptr, len)。
/// len 是**码元数**（不是字节数）——Canonical ABI 的 string 长度按码元计。
pub fn cabi_lower_string(s : String) -> (Int, Int) {
  let units = s.length()
  let byte_len = units * 2
  let ptr = cabi_realloc(0, 0, 2, byte_len)
  for i in 0..<units {
    let cp = s[i].to_int()
    mem_store8(ptr + i * 2, cp & 0xFF)
    mem_store8(ptr + i * 2 + 1, (cp >> 8) & 0xFF)
  }
  (ptr, units)
}

///|
/// 从线性内存按 **UTF-16LE** 提升字符串。
pub fn cabi_lift_string(ptr : Int, len : Int) -> String {
  let out = StringBuilder()
  for i in 0..<len {
    let lo = mem_load8(ptr + i * 2)
    let hi = mem_load8(ptr + i * 2 + 1)
    let cp = lo | (hi << 8)
    out.write_char(cp.unsafe_to_char())
  }
  out.to_string()
}

///|
/// 写 i32 到线性内存（公开包装）。
pub fn store32(ptr : Int, val : Int) -> Unit {
  mem_store32(ptr, val)
}

///|
/// 读 i32 自线性内存（公开包装）。
pub fn load32(ptr : Int) -> Int {
  mem_load32(ptr)
}
