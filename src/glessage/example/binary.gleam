//// 二进制与扩展类型示例：`Bin` 承载任意原始字节，`Ext` 以不透明方式处理
//// 扩展类型（例如 MessagePack 预定义的 timestamp，type = -1，原样通过）。
////
//// 运行：
////
//// ```sh
//// gleam run -m glessage/example/binary
//// ```

import gleam/bit_array
import gleam/int
import gleam/io
import glessage
import glessage/types

pub fn main() {
  let blob = glessage.bin(<<1, 2, 3, 0xff>>)
  let ext = glessage.ext(-1, <<0, 0, 0, 0>>)
  // timestamp，不透明
  let value = glessage.array([blob, ext])

  let assert Ok(bytes) = glessage.encode(value)
  io.println("encoded: " <> bit_array.base16_encode(bytes))

  let assert Ok(decoded) = glessage.decode_one(bytes)
  case decoded {
    types.Array([types.Bin(b), types.Ext(kind, data)]) ->
      io.println(
        "bin("
        <> int.to_string(bit_array.byte_size(b))
        <> " bytes), ext(kind="
        <> int.to_string(kind)
        <> ", data="
        <> bit_array.base16_encode(data)
        <> ")",
      )
    _ -> io.println("unexpected shape")
  }
}
