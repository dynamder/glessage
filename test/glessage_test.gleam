import gleam/bit_array
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import glessage
import glessage/types

pub fn main() {
  gleeunit.main()
}

// ---------------------------------------------------------------
// golden bytes — hand-computed from the MessagePack specification
// ---------------------------------------------------------------

pub fn nil_golden_test() {
  should.equal(glessage.encode(glessage.nil()), Ok(<<0xc0>>))
}

pub fn bool_golden_test() {
  should.equal(glessage.encode(glessage.bool(True)), Ok(<<0xc3>>))
  should.equal(glessage.encode(glessage.bool(False)), Ok(<<0xc2>>))
}

pub fn uint_golden_test() {
  should.equal(glessage.encode(glessage.uint(0)), Ok(<<0x00>>))
  should.equal(glessage.encode(glessage.uint(127)), Ok(<<0x7f>>))
  should.equal(glessage.encode(glessage.uint(128)), Ok(<<0xcc, 0x80>>))
  should.equal(glessage.encode(glessage.uint(255)), Ok(<<0xcc, 0xff>>))
  should.equal(glessage.encode(glessage.uint(256)), Ok(<<0xcd, 0x01, 0x00>>))
  should.equal(glessage.encode(glessage.uint(65_535)), Ok(<<0xcd, 0xff, 0xff>>))
  should.equal(
    glessage.encode(glessage.uint(65_536)),
    Ok(<<0xce, 0x00, 0x01, 0x00, 0x00>>),
  )
  should.equal(
    glessage.encode(glessage.uint(4_294_967_295)),
    Ok(<<0xce, 0xff, 0xff, 0xff, 0xff>>),
  )
  should.equal(
    glessage.encode(glessage.uint(4_294_967_296)),
    Ok(<<0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00>>),
  )
  should.equal(
    glessage.encode(glessage.uint(18_446_744_073_709_551_615)),
    Ok(<<0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff>>),
  )
}

pub fn int_golden_test() {
  should.equal(glessage.encode(glessage.int(-1)), Ok(<<0xff>>))
  should.equal(glessage.encode(glessage.int(-32)), Ok(<<0xe0>>))
  should.equal(glessage.encode(glessage.int(-33)), Ok(<<0xd0, 0xdf>>))
  should.equal(glessage.encode(glessage.int(-128)), Ok(<<0xd0, 0x80>>))
  should.equal(glessage.encode(glessage.int(-129)), Ok(<<0xd1, 0xff, 0x7f>>))
  should.equal(glessage.encode(glessage.int(-32_768)), Ok(<<0xd1, 0x80, 0x00>>))
  should.equal(
    glessage.encode(glessage.int(-32_769)),
    Ok(<<0xd2, 0xff, 0xff, 0x7f, 0xff>>),
  )
  should.equal(
    glessage.encode(glessage.int(-2_147_483_648)),
    Ok(<<0xd2, 0x80, 0x00, 0x00, 0x00>>),
  )
  should.equal(
    glessage.encode(glessage.int(-2_147_483_649)),
    Ok(<<0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff>>),
  )
  should.equal(
    glessage.encode(glessage.int(-9_223_372_036_854_775_808)),
    Ok(<<0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>),
  )
  // non-negative Ints encode in their minimal unsigned form
  should.equal(glessage.encode(glessage.int(5)), Ok(<<0x05>>))
}

pub fn float_golden_test() {
  should.equal(
    glessage.encode(glessage.float(0.0)),
    Ok(<<0xcb, 0, 0, 0, 0, 0, 0, 0, 0>>),
  )
  should.equal(
    glessage.encode(glessage.float(1.0)),
    Ok(<<0xcb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0>>),
  )
  should.equal(
    glessage.encode(glessage.float(-1.0)),
    Ok(<<0xcb, 0xbf, 0xf0, 0, 0, 0, 0, 0, 0>>),
  )
  should.equal(
    glessage.encode(glessage.float(0.5)),
    Ok(<<0xcb, 0x3f, 0xe0, 0, 0, 0, 0, 0, 0>>),
  )
}

pub fn str_golden_test() {
  should.equal(glessage.encode(glessage.str("")), Ok(<<0xa0>>))
  should.equal(glessage.encode(glessage.str("a")), Ok(<<0xa1, 0x61>>))
  should.equal(
    glessage.encode(glessage.str("hello")),
    Ok(<<0xa5, 0x68, 0x65, 0x6c, 0x6c, 0x6f>>),
  )
  // UTF-8 multi-byte: 中 = e4 b8 ad, 文 = e6 96 87 (6 bytes -> fixstr)
  should.equal(
    glessage.encode(glessage.str("中文")),
    Ok(<<0xa6, 0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87>>),
  )
}

pub fn str_str8_str16_test() {
  let s32 = string.repeat("a", 32)
  let s256 = string.repeat("a", 256)
  should.equal(glessage.encode(glessage.str(s32)), Ok(<<0xd9, 0x20, s32:utf8>>))
  should.equal(
    glessage.encode(glessage.str(s256)),
    Ok(<<0xda, 0x01, 0x00, s256:utf8>>),
  )
}

pub fn bin_golden_test() {
  should.equal(glessage.encode(glessage.bin(<<>>)), Ok(<<0xc4, 0x00>>))
  should.equal(
    glessage.encode(glessage.bin(<<1, 2, 3>>)),
    Ok(<<0xc4, 0x03, 1, 2, 3>>),
  )
  let big = bit_array.concat(list.repeat(<<0xab>>, 256))
  should.equal(
    glessage.encode(glessage.bin(big)),
    Ok(<<0xc5, 0x01, 0x00, big:bits>>),
  )
}

pub fn array_golden_test() {
  should.equal(glessage.encode(glessage.array([])), Ok(<<0x90>>))
  should.equal(
    glessage.encode(
      glessage.array([glessage.uint(1), glessage.uint(2), glessage.uint(3)]),
    ),
    Ok(<<0x93, 0x01, 0x02, 0x03>>),
  )
  let items = list.repeat(glessage.uint(1), 16)
  let payload = bit_array.concat(list.repeat(<<0x01>>, 16))
  should.equal(
    glessage.encode(glessage.array(items)),
    Ok(<<0xdc, 0x00, 0x10, payload:bits>>),
  )
}

pub fn map_golden_test() {
  should.equal(glessage.encode(glessage.map([])), Ok(<<0x80>>))
  should.equal(
    glessage.encode(glessage.map([#(glessage.str("a"), glessage.uint(1))])),
    Ok(<<0x81, 0xa1, 0x61, 0x01>>),
  )
  let pairs = list.repeat(#(glessage.str("k"), glessage.uint(1)), 16)
  let payload = bit_array.concat(list.repeat(<<0xa1, 0x6b, 0x01>>, 16))
  should.equal(
    glessage.encode(glessage.map(pairs)),
    Ok(<<0xde, 0x00, 0x10, payload:bits>>),
  )
}

// ---------------------------------------------------------------
// decoding — golden bytes back to values
// ---------------------------------------------------------------

pub fn decode_golden_test() {
  should.equal(glessage.decode_one(<<0xc0>>), Ok(glessage.nil()))
  should.equal(glessage.decode_one(<<0xc3>>), Ok(glessage.bool(True)))
  should.equal(glessage.decode_one(<<0xc2>>), Ok(glessage.bool(False)))
  should.equal(glessage.decode_one(<<0x7f>>), Ok(glessage.uint(127)))
  should.equal(glessage.decode_one(<<0xff>>), Ok(glessage.int(-1)))
  should.equal(glessage.decode_one(<<0xe0>>), Ok(glessage.int(-32)))
  should.equal(glessage.decode_one(<<0xcc, 0x80>>), Ok(glessage.uint(128)))
  should.equal(
    glessage.decode_one(<<0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff>>),
    Ok(glessage.uint(18_446_744_073_709_551_615)),
  )
  should.equal(
    glessage.decode_one(<<0xd3, 0x80, 0, 0, 0, 0, 0, 0, 0>>),
    Ok(glessage.int(-9_223_372_036_854_775_808)),
  )
  should.equal(
    glessage.decode_one(<<0xcb, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0>>),
    Ok(glessage.float(1.0)),
  )
  // float32 is accepted on decode and promoted to float64
  should.equal(
    glessage.decode_one(<<0xca, 0x3f, 0x80, 0, 0>>),
    Ok(glessage.float(1.0)),
  )
  should.equal(glessage.decode_one(<<0xa1, 0x61>>), Ok(glessage.str("a")))
  should.equal(
    glessage.decode_one(<<0xa6, 0xe4, 0xb8, 0xad, 0xe6, 0x96, 0x87>>),
    Ok(glessage.str("中文")),
  )
  should.equal(
    glessage.decode_one(<<0xd9, 0x20, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":utf8>>),
    Ok(glessage.str(string.repeat("a", 32))),
  )
  should.equal(
    glessage.decode_one(<<0xc4, 0x03, 1, 2, 3>>),
    Ok(glessage.bin(<<1, 2, 3>>)),
  )
  should.equal(
    glessage.decode_one(<<0x93, 0x01, 0x02, 0x03>>),
    Ok(glessage.array([glessage.uint(1), glessage.uint(2), glessage.uint(3)])),
  )
  should.equal(
    glessage.decode_one(<<0x81, 0xa1, 0x61, 0x01>>),
    Ok(glessage.map([#(glessage.str("a"), glessage.uint(1))])),
  )
}

pub fn decode_nested_test() {
  // {"a": [1, 2, 3], "b": {}}
  let bytes = <<0x82, 0xa1, 0x61, 0x93, 0x01, 0x02, 0x03, 0xa1, 0x62, 0x80>>
  let expected =
    glessage.map([
      #(
        glessage.str("a"),
        glessage.array([glessage.uint(1), glessage.uint(2), glessage.uint(3)]),
      ),
      #(glessage.str("b"), glessage.map([])),
    ])
  should.equal(glessage.decode_one(bytes), Ok(expected))
}

pub fn decode_streaming_test() {
  let bytes = <<0x01, 0x02, 0x03>>
  let assert Ok(#(first, rest1)) = glessage.decode(bytes)
  should.equal(first, glessage.uint(1))
  let assert Ok(#(second, rest2)) = glessage.decode(rest1)
  should.equal(second, glessage.uint(2))
  let assert Ok(#(third, rest3)) = glessage.decode(rest2)
  should.equal(third, glessage.uint(3))
  should.equal(rest3, <<>>)
}

// ---------------------------------------------------------------
// round trips
// ---------------------------------------------------------------

pub fn round_trip_test() {
  let values = [
    glessage.nil(),
    glessage.bool(True),
    glessage.bool(False),
    glessage.uint(0),
    glessage.uint(127),
    glessage.uint(128),
    glessage.uint(65_535),
    glessage.uint(65_536),
    glessage.uint(18_446_744_073_709_551_615),
    glessage.int(-1),
    glessage.int(-32),
    glessage.int(-33),
    glessage.int(-128),
    glessage.int(-129),
    glessage.int(-9_223_372_036_854_775_808),
    glessage.float(0.0),
    glessage.float(1.0),
    glessage.float(-1.0),
    glessage.float(0.1),
    glessage.float(3.141592653589793),
    glessage.str(""),
    glessage.str("hello world"),
    glessage.str("中文测试"),
    glessage.bin(<<>>),
    glessage.bin(<<1, 2, 3>>),
    glessage.array([]),
    glessage.array([glessage.uint(1), glessage.str("two"), glessage.nil()]),
    glessage.map([]),
    glessage.map([#(glessage.str("k"), glessage.uint(1))]),
    glessage.map([
      #(glessage.str("a"), glessage.array([glessage.uint(1), glessage.uint(2)])),
      #(
        glessage.str("b"),
        glessage.map([#(glessage.str("c"), glessage.bool(False))]),
      ),
    ]),
    glessage.ext(0, <<1, 2, 3>>),
    glessage.ext(-1, <<0, 0, 0, 0>>),
    glessage.ext(127, <<1>>),
    glessage.ext(-128, <<>>),
  ]
  list.each(values, fn(value) {
    let assert Ok(bytes) = glessage.encode(value)
    let assert Ok(decoded) = glessage.decode_one(bytes)
    should.equal(decoded, value)
  })
}

pub fn non_negative_int_encodes_as_uint_test() {
  let assert Ok(bytes) = glessage.encode(glessage.int(5))
  should.equal(bytes, <<0x05>>)
  let assert Ok(decoded) = glessage.decode_one(bytes)
  should.equal(decoded, glessage.uint(5))
}

// ---------------------------------------------------------------
// error paths
// ---------------------------------------------------------------

pub fn error_empty_test() {
  should.equal(glessage.decode_one(<<>>), Error(types.UnexpectedEnd))
}

pub fn error_truncated_test() {
  should.equal(glessage.decode_one(<<0xcc>>), Error(types.UnexpectedEnd))
  should.equal(glessage.decode_one(<<0xcd, 0x01>>), Error(types.UnexpectedEnd))
  should.equal(
    glessage.decode_one(<<0xa5, 0x61, 0x62>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0x93, 0x01, 0x02>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(glessage.decode_one(<<0xcb, 0x3f>>), Error(types.UnexpectedEnd))
  should.equal(
    glessage.decode_one(<<0xc4, 0x05, 1>>),
    Error(types.UnexpectedEnd),
  )
}

pub fn error_reserved_test() {
  should.equal(glessage.decode_one(<<0xc1>>), Error(types.ReservedTypeCode))
}

// ---------------------------------------------------------------
// extension types (fixext1..16, ext8/16/32)
// ---------------------------------------------------------------

pub fn ext_golden_test() {
  // fixext 1: kind 0, 1-byte data
  should.equal(
    glessage.encode(glessage.ext(0, <<0xab>>)),
    Ok(<<0xd4, 0x00, 0xab>>),
  )
  // fixext 4: kind -1 (the predefined timestamp type, handled opaquely)
  should.equal(
    glessage.encode(glessage.ext(-1, <<1, 2, 3, 4>>)),
    Ok(<<0xd6, 0xff, 1, 2, 3, 4>>),
  )
  // fixext 8 / 16
  should.equal(
    glessage.encode(glessage.ext(5, <<1, 2, 3, 4, 5, 6, 7, 8>>)),
    Ok(<<0xd7, 0x05, 1, 2, 3, 4, 5, 6, 7, 8>>),
  )
  let sixteen = bit_array.concat(list.repeat(<<0x11>>, 16))
  should.equal(
    glessage.encode(glessage.ext(5, sixteen)),
    Ok(<<0xd8, 0x05, sixteen:bits>>),
  )
  // ext 8: kind -128 encodes as byte 0x80
  should.equal(
    glessage.encode(glessage.ext(-128, <<1, 2, 3>>)),
    Ok(<<0xc7, 0x03, 0x80, 1, 2, 3>>),
  )
  // ext 8 with 0-length data
  should.equal(glessage.encode(glessage.ext(5, <<>>)), Ok(<<0xc7, 0x00, 0x05>>))
  // ext 16: 256-byte data
  let big = bit_array.concat(list.repeat(<<0xab>>, 256))
  should.equal(
    glessage.encode(glessage.ext(7, big)),
    Ok(<<0xc8, 0x01, 0x00, 0x07, big:bits>>),
  )
}

pub fn ext_decode_test() {
  should.equal(
    glessage.decode_one(<<0xd4, 0x00, 0xab>>),
    Ok(glessage.ext(0, <<0xab>>)),
  )
  should.equal(
    glessage.decode_one(<<0xd6, 0xff, 1, 2, 3, 4>>),
    Ok(glessage.ext(-1, <<1, 2, 3, 4>>)),
  )
  should.equal(
    glessage.decode_one(<<0xc7, 0x03, 0x80, 1, 2, 3>>),
    Ok(glessage.ext(-128, <<1, 2, 3>>)),
  )
  should.equal(
    glessage.decode_one(<<0xc7, 0x00, 0x05>>),
    Ok(glessage.ext(5, <<>>)),
  )
  // truncated extensions
  should.equal(
    glessage.decode_one(<<0xc7, 0x05, 0x00, 1>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(glessage.decode_one(<<0xd4, 0x00>>), Error(types.UnexpectedEnd))
}

pub fn ext_encode_range_test() {
  should.equal(
    glessage.encode(glessage.ext(128, <<1>>)),
    Error(types.IntegerOutOfRange(128)),
  )
  should.equal(
    glessage.encode(glessage.ext(-129, <<1>>)),
    Error(types.IntegerOutOfRange(-129)),
  )
}

pub fn error_invalid_utf8_test() {
  should.equal(glessage.decode_one(<<0xa1, 0xff>>), Error(types.InvalidUtf8))
  should.equal(
    glessage.decode_one(<<0xa2, 0xc3, 0x28>>),
    Error(types.InvalidUtf8),
  )
}

pub fn error_trailing_bytes_test() {
  should.equal(glessage.decode_one(<<0x01, 0x02>>), Error(types.TrailingBytes))
  should.equal(
    glessage.decode_one(<<0x81, 0xa1, 0x61, 0x01, 0xff>>),
    Error(types.TrailingBytes),
  )
}

pub fn error_not_byte_aligned_test() {
  should.equal(glessage.decode(<<0x01:4>>), Error(types.NotByteAligned))
}

pub fn error_encode_range_test() {
  should.equal(
    glessage.encode(glessage.uint(-1)),
    Error(types.IntegerOutOfRange(-1)),
  )
  should.equal(
    glessage.encode(glessage.uint(18_446_744_073_709_551_616)),
    Error(types.IntegerOutOfRange(18_446_744_073_709_551_616)),
  )
  should.equal(
    glessage.encode(glessage.int(-9_223_372_036_854_775_809)),
    Error(types.IntegerOutOfRange(-9_223_372_036_854_775_809)),
  )
}
