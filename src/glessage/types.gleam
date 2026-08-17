//// glessage 的值模型与错误类型。
////
//// 本模块是**叶子模块**（不 import 任何其他 glessage 模块），公开可见以便
//// 使用者对 `MsgValue` 做模式匹配：`types.Map(...)`、`types.UInt(...)`、
//// `types.Str(...)` 等。常用入口（构造器函数、`encode`/`decode`/`decode_one`）
//// 在根模块 `glessage`。

/// A MessagePack value.
pub type MsgValue {
  /// The `nil` value.
  Nil
  /// A boolean.
  Bool(Bool)
  /// A signed integer. Non-negative values are encoded in their minimal
  /// unsigned form (positive fixint or `uint8..64`) and therefore decode
  /// back as `UInt`.
  Int(Int)
  /// An unsigned integer in `0 .. 2^64-1`.
  UInt(Int)
  /// A 64-bit IEEE 754 float.
  Float(Float)
  /// A UTF-8 string.
  Str(String)
  /// Raw binary data.
  Bin(BitArray)
  /// An array of values.
  Array(List(MsgValue))
  /// A map, as a list of key/value pairs. Keys are not de-duplicated.
  Map(List(#(MsgValue, MsgValue)))
  /// An extension value: a signed 8-bit type (`-128 .. 127`) and a byte
  /// array. Decoded as opaque data — no timestamp or other semantics are
  /// applied.
  Ext(kind: Int, data: BitArray)
}

/// An error that occurred while encoding a value.
pub type EncodeError {
  /// The integer does not fit into MessagePack's `int64`/`uint64` range.
  IntegerOutOfRange(Int)
  /// The value exceeds the largest size the wire format can express
  /// (a string, array or map larger than `2^32-1` units).
  ValueTooLarge(String)
}

/// An error that occurred while decoding bytes.
pub type DecodeError {
  /// The input ended before the value was complete.
  UnexpectedEnd
  /// The input is not a whole number of bytes.
  NotByteAligned
  /// Marker byte `0xc1`, which the MessagePack specification reserves.
  ReservedTypeCode
  /// A marker byte that is not a valid MessagePack marker.
  InvalidMarker(Int)
  /// A string segment that is not valid UTF-8.
  InvalidUtf8
  /// Bytes were left over after decoding a single value (`decode_one`).
  TrailingBytes
}
