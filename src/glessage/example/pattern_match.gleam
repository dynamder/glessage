//// 模式匹配示例：解码一段 wire 字节，用 `glessage/types` 的构造器做模式匹配
//// 提取字段——把 glessage 用于自定义协议（如 loom）时的常见姿势。
////
//// 运行：
////
//// ```sh
//// gleam run -m glessage/example/pattern_match
//// ```

import gleam/io
import gleam/list
import glessage
import glessage/types

pub fn main() {
  // {"op": "hello", "version": 1}
  let bytes = <<
    0x82, 0xa2, 0x6f, 0x70, 0xa5, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0xa7, 0x76, 0x65,
    0x72, 0x73, 0x69, 0x6f, 0x6e, 0x01,
  >>

  let assert Ok(value) = glessage.decode_one(bytes)
  case value {
    types.Map(entries) -> {
      case list.find(entries, fn(pair) { pair.0 == types.Str("op") }) {
        Ok(#(_, types.Str(op))) -> io.println("op = " <> op)
        _ -> io.println("missing op")
      }
    }
    _ -> io.println("not a map")
  }
}
