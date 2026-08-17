//// MessagePack 编码器（包内部实现）。
////
//// 把 `MsgValue` 编码为 MessagePack 字节序列；格式选择遵循规范
//// 「尽量使用最小格式」原则（见 SPEC_COMPLIANCE.md §3.3）。

import gleam/bit_array
import gleam/list
import gleam/result
import glessage/types.{
  type EncodeError, type MsgValue, Array, Bin, Bool, Ext, Float, Int,
  IntegerOutOfRange, Map, Nil, Str, UInt, ValueTooLarge,
}

/// Encodes a value into MessagePack bytes.
pub fn encode(value: MsgValue) -> Result(BitArray, EncodeError) {
  case value {
    Nil -> Ok(<<0xc0>>)
    Bool(True) -> Ok(<<0xc3>>)
    Bool(False) -> Ok(<<0xc2>>)
    Int(i) -> encode_int(i)
    UInt(i) -> encode_uint(i)
    Float(f) -> Ok(<<0xcb, f:float-size(64)>>)
    Str(s) -> encode_str(s)
    Bin(b) -> encode_bin(b)
    Array(items) -> encode_array(items)
    Map(entries) -> encode_map(entries)
    Ext(kind, data) -> encode_ext(kind, data)
  }
}

fn encode_int(i: Int) -> Result(BitArray, EncodeError) {
  case i {
    i if i >= 0 -> encode_uint(i)
    i if i >= -0x20 -> {
      let byte = i + 0x100
      Ok(<<byte:8>>)
    }
    i if i >= -0x80 -> {
      let byte = i + 0x100
      Ok(<<0xd0, byte:8>>)
    }
    i if i >= -0x8000 -> {
      let value = i + 0x10000
      Ok(<<0xd1, value:16>>)
    }
    i if i >= -0x8000_0000 -> {
      let value = i + 0x1_0000_0000
      Ok(<<0xd2, value:32>>)
    }
    i if i >= -0x8000_0000_0000_0000 -> {
      let value = i + 0x1_0000_0000_0000_0000
      Ok(<<0xd3, value:64>>)
    }
    _ -> Error(IntegerOutOfRange(i))
  }
}

fn encode_uint(i: Int) -> Result(BitArray, EncodeError) {
  case i {
    i if i < 0 -> Error(IntegerOutOfRange(i))
    i if i <= 0x7f -> Ok(<<i:8>>)
    i if i <= 0xff -> Ok(<<0xcc, i:8>>)
    i if i <= 0xffff -> Ok(<<0xcd, i:16>>)
    i if i <= 0xffff_ffff -> Ok(<<0xce, i:32>>)
    i if i <= 0xffff_ffff_ffff_ffff -> Ok(<<0xcf, i:64>>)
    _ -> Error(IntegerOutOfRange(i))
  }
}

fn encode_str(s: String) -> Result(BitArray, EncodeError) {
  let bytes = bit_array.from_string(s)
  let size = bit_array.byte_size(bytes)
  case size {
    n if n <= 0x1f -> {
      let header = 0xa0 + n
      Ok(<<header:8, bytes:bits>>)
    }
    n if n <= 0xff -> Ok(<<0xd9, n:8, bytes:bits>>)
    n if n <= 0xffff -> Ok(<<0xda, n:16, bytes:bits>>)
    n if n <= 0xffff_ffff -> Ok(<<0xdb, n:32, bytes:bits>>)
    _ -> Error(ValueTooLarge("string"))
  }
}

fn encode_bin(b: BitArray) -> Result(BitArray, EncodeError) {
  let size = bit_array.byte_size(b)
  case size {
    n if n <= 0xff -> Ok(<<0xc4, n:8, b:bits>>)
    n if n <= 0xffff -> Ok(<<0xc5, n:16, b:bits>>)
    n if n <= 0xffff_ffff -> Ok(<<0xc6, n:32, b:bits>>)
    _ -> Error(ValueTooLarge("binary"))
  }
}

fn encode_array(items: List(MsgValue)) -> Result(BitArray, EncodeError) {
  let count = list.length(items)
  use header <- result.try(array_header(count))
  use payload <- result.try(encode_all(items))
  Ok(<<header:bits, payload:bits>>)
}

fn array_header(n: Int) -> Result(BitArray, EncodeError) {
  case n {
    n if n <= 0x0f -> {
      let header = 0x90 + n
      Ok(<<header:8>>)
    }
    n if n <= 0xffff -> Ok(<<0xdc, n:16>>)
    n if n <= 0xffff_ffff -> Ok(<<0xdd, n:32>>)
    _ -> Error(ValueTooLarge("array"))
  }
}

fn encode_all(items: List(MsgValue)) -> Result(BitArray, EncodeError) {
  case items {
    [] -> Ok(<<>>)
    [first, ..rest] -> {
      use f <- result.try(encode(first))
      use r <- result.try(encode_all(rest))
      Ok(<<f:bits, r:bits>>)
    }
  }
}

fn encode_map(
  entries: List(#(MsgValue, MsgValue)),
) -> Result(BitArray, EncodeError) {
  let count = list.length(entries)
  use header <- result.try(map_header(count))
  use payload <- result.try(encode_pairs(entries))
  Ok(<<header:bits, payload:bits>>)
}

fn map_header(n: Int) -> Result(BitArray, EncodeError) {
  case n {
    n if n <= 0x0f -> {
      let header = 0x80 + n
      Ok(<<header:8>>)
    }
    n if n <= 0xffff -> Ok(<<0xde, n:16>>)
    n if n <= 0xffff_ffff -> Ok(<<0xdf, n:32>>)
    _ -> Error(ValueTooLarge("map"))
  }
}

fn encode_pairs(
  entries: List(#(MsgValue, MsgValue)),
) -> Result(BitArray, EncodeError) {
  case entries {
    [] -> Ok(<<>>)
    [#(key, value), ..rest] -> {
      use k <- result.try(encode(key))
      use v <- result.try(encode(value))
      use r <- result.try(encode_pairs(rest))
      Ok(<<k:bits, v:bits, r:bits>>)
    }
  }
}

fn encode_ext(kind: Int, data: BitArray) -> Result(BitArray, EncodeError) {
  let size = bit_array.byte_size(data)
  case size {
    _ if kind < -0x80 || kind > 0x7f -> Error(IntegerOutOfRange(kind))
    1 -> Ok(<<0xd4, signed_byte(kind):8, data:bits>>)
    2 -> Ok(<<0xd5, signed_byte(kind):8, data:bits>>)
    4 -> Ok(<<0xd6, signed_byte(kind):8, data:bits>>)
    8 -> Ok(<<0xd7, signed_byte(kind):8, data:bits>>)
    16 -> Ok(<<0xd8, signed_byte(kind):8, data:bits>>)
    n if n <= 0xff -> Ok(<<0xc7, n:8, signed_byte(kind):8, data:bits>>)
    n if n <= 0xffff -> Ok(<<0xc8, n:16, signed_byte(kind):8, data:bits>>)
    n if n <= 0xffff_ffff -> Ok(<<0xc9, n:32, signed_byte(kind):8, data:bits>>)
    _ -> Error(ValueTooLarge("extension"))
  }
}

/// Encodes a signed 8-bit integer (`-128 .. 127`) as its two's complement
/// byte value (`0 .. 255`).
fn signed_byte(kind: Int) -> Int {
  case kind < 0 {
    True -> kind + 0x100
    False -> kind
  }
}
