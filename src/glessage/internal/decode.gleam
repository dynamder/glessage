//// MessagePack 解码器（包内部实现）。
////
//// 从字节流解码 `MsgValue`；对任意输入保证不崩溃、不悬挂：
//// 所有长度前缀先做字节数校验再切片，病态长度在首个元素解析时立即失败。

import gleam/bit_array
import gleam/list
import gleam/result
import glessage/types.{
  type DecodeError, type MsgValue, Array, Bin, Bool, Ext, Float, Int,
  InvalidMarker, InvalidUtf8, Map, Nil, NotByteAligned, ReservedTypeCode, Str,
  TrailingBytes, UInt, UnexpectedEnd,
}

/// Decodes one MessagePack value from the start of the bit array, returning
/// the value together with the remaining bytes so that several concatenated
/// values can be decoded in sequence.
pub fn decode(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bit_array.bit_size(bits) % 8 {
    0 -> decode_value(bits)
    _ -> Error(NotByteAligned)
  }
}

/// Decodes exactly one MessagePack value from the bit array. Fails with
/// `TrailingBytes` if anything follows the value.
pub fn decode_one(bits: BitArray) -> Result(MsgValue, DecodeError) {
  use pair <- result.try(decode(bits))
  let #(value, rest) = pair
  case rest {
    <<>> -> Ok(value)
    _ -> Error(TrailingBytes)
  }
}

fn decode_value(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<b:8, rest:bytes>> -> decode_marker(b, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_marker(
  b: Int,
  rest: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case b {
    b if b <= 0x7f -> Ok(#(UInt(b), rest))
    0xc0 -> Ok(#(Nil, rest))
    0xc1 -> Error(ReservedTypeCode)
    0xc2 -> Ok(#(Bool(False), rest))
    0xc3 -> Ok(#(Bool(True), rest))
    b if b >= 0xe0 -> Ok(#(Int(b - 0x100), rest))
    0xc7 -> decode_ext8(rest)
    0xc8 -> decode_ext16(rest)
    0xc9 -> decode_ext32(rest)
    0xca -> decode_float32(rest)
    0xcb -> decode_float64(rest)
    0xd4 -> decode_fixext(1, rest)
    0xd5 -> decode_fixext(2, rest)
    0xd6 -> decode_fixext(4, rest)
    0xd7 -> decode_fixext(8, rest)
    0xd8 -> decode_fixext(16, rest)
    0xc4 -> decode_bin8(rest)
    0xc5 -> decode_bin16(rest)
    0xc6 -> decode_bin32(rest)
    0xcc -> decode_uint8(rest)
    0xcd -> decode_uint16(rest)
    0xce -> decode_uint32(rest)
    0xcf -> decode_uint64(rest)
    0xd0 -> decode_int8(rest)
    0xd1 -> decode_int16(rest)
    0xd2 -> decode_int32(rest)
    0xd3 -> decode_int64(rest)
    0xd9 -> decode_str8(rest)
    0xda -> decode_str16(rest)
    0xdb -> decode_str32(rest)
    0xdc -> decode_array16(rest)
    0xdd -> decode_array32(rest)
    0xde -> decode_map16(rest)
    0xdf -> decode_map32(rest)
    b if b >= 0xa0 -> decode_str(b - 0xa0, rest)
    b if b >= 0x90 -> decode_array_n(b - 0x90, rest)
    b if b >= 0x80 -> decode_map_n(b - 0x80, rest)
    _ -> Error(InvalidMarker(b))
  }
}

fn decode_uint8(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:8, rest:bytes>> -> Ok(#(UInt(v), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_uint16(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:16, rest:bytes>> -> Ok(#(UInt(v), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_uint32(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:32, rest:bytes>> -> Ok(#(UInt(v), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_uint64(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:64, rest:bytes>> -> Ok(#(UInt(v), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_int8(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:8, rest:bytes>> -> Ok(#(Int(from_twos(v, 8)), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_int16(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:16, rest:bytes>> -> Ok(#(Int(from_twos(v, 16)), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_int32(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:32, rest:bytes>> -> Ok(#(Int(from_twos(v, 32)), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_int64(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<v:64, rest:bytes>> -> Ok(#(Int(from_twos(v, 64)), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_float32(
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<f:float-size(32), rest:bytes>> -> Ok(#(Float(f), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_float64(
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<f:float-size(64), rest:bytes>> -> Ok(#(Float(f), rest))
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_str8(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:8, rest:bytes>> -> decode_str(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_str16(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:16, rest:bytes>> -> decode_str(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_str32(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:32, rest:bytes>> -> decode_str(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_bin8(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:8, rest:bytes>> -> decode_bin(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_bin16(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:16, rest:bytes>> -> decode_bin(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_bin32(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:32, rest:bytes>> -> decode_bin(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_fixext(
  n: Int,
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<kind:8, rest:bytes>> -> decode_ext_with_len(n, from_twos(kind, 8), rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_ext8(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<len:8, kind:8, rest:bytes>> ->
      decode_ext_with_len(len, from_twos(kind, 8), rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_ext16(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<len:16, kind:8, rest:bytes>> ->
      decode_ext_with_len(len, from_twos(kind, 8), rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_ext32(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<len:32, kind:8, rest:bytes>> ->
      decode_ext_with_len(len, from_twos(kind, 8), rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_ext_with_len(
  len: Int,
  kind: Int,
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bit_array.byte_size(bits) < len {
    True -> Error(UnexpectedEnd)
    False -> {
      use data <- result.try(
        bit_array.slice(bits, at: 0, take: len)
        |> result.map_error(fn(_) { UnexpectedEnd }),
      )
      use rest <- result.try(rest_after(bits, len))
      Ok(#(Ext(kind, data), rest))
    }
  }
}

fn decode_array16(
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:16, rest:bytes>> -> decode_array_n(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_array32(
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:32, rest:bytes>> -> decode_array_n(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_map16(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:16, rest:bytes>> -> decode_map_n(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_map32(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bits {
    <<n:32, rest:bytes>> -> decode_map_n(n, rest)
    _ -> Error(UnexpectedEnd)
  }
}

fn decode_str(
  len: Int,
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bit_array.byte_size(bits) < len {
    True -> Error(UnexpectedEnd)
    False -> {
      use sliced <- result.try(
        bit_array.slice(bits, at: 0, take: len)
        |> result.map_error(fn(_) { UnexpectedEnd }),
      )
      use s <- result.try(
        bit_array.to_string(sliced)
        |> result.map_error(fn(_) { InvalidUtf8 }),
      )
      use rest <- result.try(rest_after(bits, len))
      Ok(#(Str(s), rest))
    }
  }
}

fn decode_bin(
  len: Int,
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case bit_array.byte_size(bits) < len {
    True -> Error(UnexpectedEnd)
    False -> {
      use sliced <- result.try(
        bit_array.slice(bits, at: 0, take: len)
        |> result.map_error(fn(_) { UnexpectedEnd }),
      )
      use rest <- result.try(rest_after(bits, len))
      Ok(#(Bin(sliced), rest))
    }
  }
}

fn rest_after(bits: BitArray, len: Int) -> Result(BitArray, DecodeError) {
  bit_array.slice(bits, at: len, take: bit_array.byte_size(bits) - len)
  |> result.map_error(fn(_) { UnexpectedEnd })
}

fn decode_array_n(
  n: Int,
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  decode_n(n, bits, [])
}

fn decode_n(
  n: Int,
  bits: BitArray,
  acc: List(MsgValue),
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case n {
    0 -> Ok(#(Array(list.reverse(acc)), bits))
    _ -> {
      use pair <- result.try(decode_value(bits))
      let #(value, rest) = pair
      decode_n(n - 1, rest, [value, ..acc])
    }
  }
}

fn decode_map_n(
  n: Int,
  bits: BitArray,
) -> Result(#(MsgValue, BitArray), DecodeError) {
  decode_map_n_loop(n, bits, [])
}

fn decode_map_n_loop(
  n: Int,
  bits: BitArray,
  acc: List(#(MsgValue, MsgValue)),
) -> Result(#(MsgValue, BitArray), DecodeError) {
  case n {
    0 -> Ok(#(Map(list.reverse(acc)), bits))
    _ -> {
      use pair <- result.try(decode_value(bits))
      let #(key, rest1) = pair
      use pair2 <- result.try(decode_value(rest1))
      let #(value, rest2) = pair2
      decode_map_n_loop(n - 1, rest2, [#(key, value), ..acc])
    }
  }
}

// ---- signed integer helpers ----

fn sign_bit(bits: Int) -> Int {
  case bits {
    8 -> 0x80
    16 -> 0x8000
    32 -> 0x8000_0000
    64 -> 0x8000_0000_0000_0000
    _ -> 0
  }
}

fn from_twos(value: Int, bits: Int) -> Int {
  case value >= sign_bit(bits) {
    True -> value - sign_bit(bits) * 2
    False -> value
  }
}
