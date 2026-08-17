//// 基础示例：构造一个值 → 编码为 MessagePack 字节 → 解码回原值。
////
//// 运行：
////
//// ```sh
//// gleam run -m glessage/example/basic
//// ```

import gleam/bit_array
import gleam/io
import glessage

pub fn main() {
  let value =
    glessage.map([
      #(glessage.str("op"), glessage.str("hello")),
      #(glessage.str("version"), glessage.uint(1)),
    ])

  let assert Ok(bytes) = glessage.encode(value)
  io.println("encoded: " <> bit_array.base16_encode(bytes))

  let assert Ok(decoded) = glessage.decode_one(bytes)
  io.println(
    "decoded round-trips: "
    <> case decoded == value {
      True -> "true"
      False -> "false"
    },
  )
}
