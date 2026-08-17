//// 流式解码示例：把多个值连续编码进同一段字节，再用 `decode` 逐个取出。
////
//// `decode` 返回「值 + 剩余字节」，适合 `{packet, N}` 帧协议等场景
//// （loom 的宿主端口协议正是这种用法）。
////
//// 运行：
////
//// ```sh
//// gleam run -m glessage/example/streaming
//// ```

import gleam/bit_array
import gleam/int
import gleam/io
import gleam/list
import glessage
import glessage/types

pub fn main() {
  let values = [
    glessage.uint(42),
    glessage.str("two"),
    glessage.array([glessage.bool(True), glessage.nil()]),
  ]
  let stream =
    bit_array.concat(
      list.map(values, fn(value) {
        let assert Ok(bytes) = glessage.encode(value)
        bytes
      }),
    )

  let assert Ok(#(first, rest)) = glessage.decode(stream)
  let assert Ok(#(second, rest)) = glessage.decode(rest)
  let assert Ok(#(third, rest)) = glessage.decode(rest)

  io.println("first:  " <> describe(first))
  io.println("second: " <> describe(second))
  io.println("third:  " <> describe(third))
  io.println("remaining bytes: " <> int.to_string(bit_array.byte_size(rest)))
}

fn describe(value: glessage.MsgValue) -> String {
  case value {
    types.UInt(n) -> "UInt(" <> int.to_string(n) <> ")"
    types.Str(s) -> "Str(" <> s <> ")"
    types.Array(items) ->
      "Array(" <> int.to_string(list.length(items)) <> " elements)"
    _ -> "other"
  }
}
