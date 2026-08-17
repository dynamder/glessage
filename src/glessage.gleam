//// glessage — a pure Gleam [MessagePack](https://msgpack.org) encoder and
//// decoder.
////
//// Everything is built on Gleam bit syntax, so this library has no native
//// code anywhere: the only dependency is `gleam_stdlib`.
////
//// ## Module layout
////
//// - `glessage` — public API: constructors, `encode`, `decode`, `decode_one`
//// - `glessage/types` — the value model (`MsgValue`) and error types; import
////   this module to pattern match on values (e.g. `types.Map(...)`)
//// - `glessage/internal/*` — encoder/decoder implementations (package-internal)
////
//// ## Supported types
////
//// - `nil`, booleans
//// - integers: positive/negative fixint, `int8..64`, `uint8..64`
//// - floats: always encoded as `float64`; `float32` is accepted on decode
//// - strings (`fixstr`, `str8..32`), binary (`bin8..32`)
//// - arrays (`fixarray`, `array16..32`), maps (`fixmap`, `map16..32`)
//// - extensions (`fixext1..16`, `ext8..32`), handled as opaque data
////
//// The wire format follows the MessagePack specification
//// (<https://github.com/msgpack/msgpack/blob/master/spec.md>); see
//// `SPEC_COMPLIANCE.md` for the detailed audit.

import glessage/internal/decode as decode_impl
import glessage/internal/encode as encode_impl
import glessage/types

/// A MessagePack value. See `glessage/types` for the constructors
/// (used when pattern matching).
pub type MsgValue =
  types.MsgValue

/// An error that occurred while encoding a value.
pub type EncodeError =
  types.EncodeError

/// An error that occurred while decoding bytes.
pub type DecodeError =
  types.DecodeError

/// Constructs the `nil` value.
pub fn nil() -> MsgValue {
  types.Nil
}

/// Constructs a boolean value.
pub fn bool(value: Bool) -> MsgValue {
  types.Bool(value)
}

/// Constructs a signed integer.
pub fn int(value: Int) -> MsgValue {
  types.Int(value)
}

/// Constructs an unsigned integer. Values outside `0 .. 2^64-1` are rejected
/// at encode time with `IntegerOutOfRange`.
pub fn uint(value: Int) -> MsgValue {
  types.UInt(value)
}

/// Constructs a float, encoded as 64-bit IEEE 754.
pub fn float(value: Float) -> MsgValue {
  types.Float(value)
}

/// Constructs a UTF-8 string.
pub fn str(value: String) -> MsgValue {
  types.Str(value)
}

/// Constructs a raw binary value.
pub fn bin(value: BitArray) -> MsgValue {
  types.Bin(value)
}

/// Constructs an array.
pub fn array(items: List(MsgValue)) -> MsgValue {
  types.Array(items)
}

/// Constructs a map from a list of key/value pairs.
pub fn map(entries: List(#(MsgValue, MsgValue))) -> MsgValue {
  types.Map(entries)
}

/// Constructs an extension value. The kind must fit in a signed 8-bit
/// integer (`-128 .. 127`) or encoding fails with `IntegerOutOfRange`.
pub fn ext(kind: Int, data: BitArray) -> MsgValue {
  types.Ext(kind, data)
}

/// Encodes a value into MessagePack bytes.
pub fn encode(value: MsgValue) -> Result(BitArray, EncodeError) {
  encode_impl.encode(value)
}

/// Decodes one MessagePack value from the start of the bit array, returning
/// the value together with the remaining bytes so that several concatenated
/// values can be decoded in sequence.
pub fn decode(bits: BitArray) -> Result(#(MsgValue, BitArray), DecodeError) {
  decode_impl.decode(bits)
}

/// Decodes exactly one MessagePack value from the bit array. Fails with
/// `TrailingBytes` if anything follows the value.
pub fn decode_one(bits: BitArray) -> Result(MsgValue, DecodeError) {
  decode_impl.decode_one(bits)
}
