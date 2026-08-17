//// Fuzz tests for glessage.
////
//// Uses a deterministic PRNG (splitmix64, wrapping 64-bit arithmetic built
//// from `gleam/int` bitwise functions) so every run exercises the same
//// corpus and failures are reproducible in CI.
////
//// Coverage:
//// - random value round trips (encode -> decode_one == original)
//// - random byte input (decode must never crash or hang)
//// - valid encodings + garbage suffix (always `TrailingBytes`)
//// - valid encodings + byte mutations (must never crash)
//// - every strict prefix of valid encodings (must never crash)
//// - pathological declared lengths (must fail fast, no hang)

import gleam/bit_array
import gleam/int
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
// deterministic PRNG — splitmix64 with 64-bit wrapping arithmetic
// ---------------------------------------------------------------

type Rng {
  Rng(state: Int)
}

const mask_64 = 0xffff_ffff_ffff_ffff

fn next_u64(rng: Rng) -> #(Int, Rng) {
  let Rng(state0) = rng
  let state = int.bitwise_and(state0 + 0x9e3779b97f4a7c15, mask_64)
  let z1 = int.bitwise_exclusive_or(state, int.bitwise_shift_right(state, 30))
  let z2 = int.bitwise_and(z1 * 0xbf58476d1ce4e5b9, mask_64)
  let z3 = int.bitwise_exclusive_or(z2, int.bitwise_shift_right(z2, 27))
  let z4 = int.bitwise_and(z3 * 0x94d049bb133111eb, mask_64)
  let out = int.bitwise_exclusive_or(z4, int.bitwise_shift_right(z4, 31))
  #(out, Rng(state))
}

fn random_int(rng: Rng, max: Int) -> #(Int, Rng) {
  let #(v, rng) = next_u64(rng)
  #(v % max, rng)
}

fn random_byte(rng: Rng) -> #(Int, Rng) {
  let #(v, rng) = next_u64(rng)
  #(int.bitwise_and(v, 0xff), rng)
}

fn random_bytes(rng: Rng, count: Int) -> #(BitArray, Rng) {
  random_bytes_loop(rng, count, <<>>)
}

fn random_bytes_loop(rng: Rng, count: Int, acc: BitArray) -> #(BitArray, Rng) {
  case count {
    0 -> #(acc, rng)
    _ -> {
      let #(b, rng) = random_byte(rng)
      random_bytes_loop(rng, count - 1, <<acc:bits, b:8>>)
    }
  }
}

fn random_bytes_len(rng: Rng, max: Int) -> #(BitArray, Rng) {
  let #(len, rng) = random_int(rng, max)
  random_bytes(rng, len)
}

fn random_uint_width(rng: Rng, width: Int) -> #(Int, Rng) {
  let #(v, rng) = next_u64(rng)
  let mask = case width {
    8 -> 0xff
    16 -> 0xffff
    32 -> 0xffff_ffff
    _ -> 0x7fff_ffff_ffff_ffff
  }
  #(int.bitwise_and(v, mask), rng)
}

// ---------------------------------------------------------------
// random value generation (bounded depth/size)
// ---------------------------------------------------------------

fn random_value(rng: Rng, depth: Int) -> #(glessage.MsgValue, Rng) {
  case depth <= 0 {
    True -> random_scalar(rng)
    False -> {
      let #(kind, rng) = random_int(rng, 10)
      case kind {
        8 -> {
          let #(size, rng) = random_int(rng, 6)
          random_array(rng, size, depth - 1, [])
        }
        9 -> {
          let #(size, rng) = random_int(rng, 6)
          random_map(rng, size, depth - 1, [])
        }
        _ -> random_scalar(rng)
      }
    }
  }
}

fn random_scalar(rng: Rng) -> #(glessage.MsgValue, Rng) {
  let #(kind, rng) = random_int(rng, 8)
  case kind {
    0 -> #(glessage.nil(), rng)
    1 -> {
      let #(b, rng) = random_int(rng, 2)
      #(glessage.bool(b == 0), rng)
    }
    2 -> {
      let #(w, rng) = random_int(rng, 4)
      let bits = case w {
        0 -> 8
        1 -> 16
        2 -> 32
        _ -> 64
      }
      let #(v, rng) = random_uint_width(rng, bits)
      #(glessage.uint(v), rng)
    }
    3 -> {
      // negative int in [-2^63, -1], always representable as int8..64
      let #(w, rng) = random_int(rng, 4)
      let bits = case w {
        0 -> 8
        1 -> 16
        2 -> 32
        _ -> 63
      }
      let #(v, rng) = random_uint_width(rng, bits)
      #(glessage.int(-v - 1), rng)
    }
    4 -> {
      let #(f, rng) = random_float(rng)
      #(glessage.float(f), rng)
    }
    5 -> {
      let #(s, rng) = random_str(rng)
      #(glessage.str(s), rng)
    }
    6 -> {
      let #(b, rng) = random_bytes_len(rng, 24)
      #(glessage.bin(b), rng)
    }
    _ -> {
      let #(k, rng) = random_byte(rng)
      let kind = case k >= 0x80 {
        True -> k - 0x100
        False -> k
      }
      let #(data, rng) = random_bytes_len(rng, 20)
      #(glessage.ext(kind, data), rng)
    }
  }
}

fn random_float(rng: Rng) -> #(Float, Rng) {
  let #(choice, rng) = random_int(rng, 6)
  case choice {
    0 -> #(0.0, rng)
    1 -> #(-0.0, rng)
    2 -> {
      let #(v, rng) = next_u64(rng)
      #(int.to_float(int.bitwise_and(v, 0x1f_ffff_ffff_ffff)), rng)
    }
    3 -> {
      let #(v, rng) = next_u64(rng)
      #(-1.0 *. int.to_float(int.bitwise_and(v, 0x1f_ffff_ffff_ffff)), rng)
    }
    4 -> {
      let #(v, rng) = next_u64(rng)
      #(0.1 *. int.to_float(v % 10_000), rng)
    }
    _ -> #(3.141592653589793, rng)
  }
}

fn random_str(rng: Rng) -> #(String, Rng) {
  let #(choice, rng) = random_int(rng, 7)
  case choice {
    0 -> #("", rng)
    1 -> #("hello", rng)
    2 -> #("中文", rng)
    3 -> #("héllo wörld 🎉", rng)
    4 -> {
      let #(len, rng) = random_int(rng, 80)
      #(string.repeat("a", len), rng)
    }
    5 -> {
      let #(len, rng) = random_int(rng, 40)
      #(string.repeat("ab", len), rng)
    }
    _ -> {
      let #(len, rng) = random_int(rng, 100)
      #(string.repeat("abcde", len), rng)
    }
  }
}

fn random_array(
  rng: Rng,
  size: Int,
  depth: Int,
  acc: List(glessage.MsgValue),
) -> #(glessage.MsgValue, Rng) {
  case size {
    0 -> #(glessage.array(list.reverse(acc)), rng)
    _ -> {
      let #(v, rng) = random_value(rng, depth)
      random_array(rng, size - 1, depth, [v, ..acc])
    }
  }
}

fn random_map(
  rng: Rng,
  size: Int,
  depth: Int,
  acc: List(#(glessage.MsgValue, glessage.MsgValue)),
) -> #(glessage.MsgValue, Rng) {
  case size {
    0 -> #(glessage.map(list.reverse(acc)), rng)
    _ -> {
      let #(k, rng) = random_value(rng, depth)
      let #(v, rng) = random_value(rng, depth)
      random_map(rng, size - 1, depth, [#(k, v), ..acc])
    }
  }
}

// ---------------------------------------------------------------
// fuzz: random value round trips
// ---------------------------------------------------------------

pub fn fuzz_round_trip_test() {
  let seeds = [0x1234_5678_9abc_def0, 1, 2, 42, 0xdead_beef]
  list.each(seeds, fn(seed) { fuzz_round_trip_seed(Rng(seed), 150) })
}

fn fuzz_round_trip_seed(rng: Rng, iterations: Int) {
  case iterations {
    0 -> Nil
    _ -> {
      let #(value, rng) = random_value(rng, 4)
      let assert Ok(bytes) = glessage.encode(value)
      let assert Ok(decoded) = glessage.decode_one(bytes)
      should.equal(decoded, value)
      fuzz_round_trip_seed(rng, iterations - 1)
    }
  }
}

// ---------------------------------------------------------------
// fuzz: random bytes must never crash or hang
// ---------------------------------------------------------------

pub fn fuzz_random_bytes_test() {
  fuzz_random_bytes_seed(Rng(7), 400, 0, 0)
  fuzz_random_bytes_seed(Rng(13), 400, 0, 0)
  fuzz_random_bytes_seed(Rng(99), 400, 0, 0)
}

fn fuzz_random_bytes_seed(rng: Rng, iterations: Int, ok: Int, err: Int) {
  case iterations {
    0 -> {
      // sanity: both paths were actually exercised
      should.equal(ok > 0, True)
      should.equal(err > 0, True)
    }
    _ -> {
      let #(len, rng) = random_int(rng, 65)
      let #(bytes, rng) = random_bytes(rng, len)
      case glessage.decode_one(bytes) {
        Ok(_) -> fuzz_random_bytes_seed(rng, iterations - 1, ok + 1, err)
        Error(_) -> fuzz_random_bytes_seed(rng, iterations - 1, ok, err + 1)
      }
    }
  }
}

// ---------------------------------------------------------------
// fuzz: valid encodings + garbage suffix -> TrailingBytes
// ---------------------------------------------------------------

pub fn fuzz_suffix_garbage_test() {
  let samples = fuzz_samples()
  list.each(samples, fn(sample) { fuzz_suffix_one(sample, Rng(0xc0ffee), 40) })
}

fn fuzz_suffix_one(sample: BitArray, rng: Rng, iterations: Int) {
  case iterations {
    0 -> Nil
    _ -> {
      // non-empty garbage suffix: decode_one must reject with TrailingBytes
      let #(len, rng) = random_int(rng, 12)
      let #(garbage, rng) = random_bytes(rng, len + 1)
      let combined = bit_array.concat([sample, garbage])
      should.equal(glessage.decode_one(combined), Error(types.TrailingBytes))
      fuzz_suffix_one(sample, rng, iterations - 1)
    }
  }
}

// ---------------------------------------------------------------
// fuzz: byte mutations of valid encodings must never crash
// ---------------------------------------------------------------

pub fn fuzz_mutation_test() {
  let samples = fuzz_samples()
  list.each(samples, fn(sample) { fuzz_mutate_one(sample, Rng(0xabcd), 60) })
}

fn fuzz_mutate_one(sample: BitArray, rng: Rng, iterations: Int) {
  case iterations {
    0 -> Nil
    _ -> {
      let len = bit_array.byte_size(sample)
      let #(pos, rng) = random_int(rng, len)
      let #(b, rng) = random_byte(rng)
      let mutated = replace_byte(sample, pos, b)
      let _ = glessage.decode_one(mutated)
      fuzz_mutate_one(sample, rng, iterations - 1)
    }
  }
}

fn replace_byte(bits: BitArray, pos: Int, b: Int) -> BitArray {
  let before = case bit_array.slice(bits, at: 0, take: pos) {
    Ok(x) -> x
    Error(_) -> <<>>
  }
  let after = case
    bit_array.slice(
      bits,
      at: pos + 1,
      take: bit_array.byte_size(bits) - pos - 1,
    )
  {
    Ok(x) -> x
    Error(_) -> <<>>
  }
  <<before:bits, b:8, after:bits>>
}

// ---------------------------------------------------------------
// fuzz: every strict prefix of valid encodings must never crash
// ---------------------------------------------------------------

pub fn fuzz_truncation_test() {
  let samples = fuzz_samples()
  list.each(samples, fuzz_truncate_one)
}

fn fuzz_truncate_one(sample: BitArray) {
  let len = bit_array.byte_size(sample)
  fuzz_truncate_loop(sample, len, 0)
}

fn fuzz_truncate_loop(sample: BitArray, len: Int, take: Int) {
  case take >= len {
    True -> Nil
    False -> {
      let prefix = case bit_array.slice(sample, at: 0, take: take) {
        Ok(x) -> x
        Error(_) -> <<>>
      }
      let _ = glessage.decode(prefix)
      let _ = glessage.decode_one(prefix)
      fuzz_truncate_loop(sample, len, take + 1)
    }
  }
}

// ---------------------------------------------------------------
// pathological declared lengths must fail fast (no hang / no overflow)
// ---------------------------------------------------------------

pub fn pathological_lengths_test() {
  should.equal(
    glessage.decode_one(<<0xdc, 0xff, 0xff>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0xdd, 0xff, 0xff, 0xff, 0xff>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0xde, 0xff, 0xff>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0xdf, 0xff, 0xff, 0xff, 0xff>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0xdb, 0xff, 0xff, 0xff, 0xff>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0xc9, 0xff, 0xff, 0xff, 0xff, 0x00>>),
    Error(types.UnexpectedEnd),
  )
  should.equal(
    glessage.decode_one(<<0xc6, 0xff, 0xff, 0xff, 0xff>>),
    Error(types.UnexpectedEnd),
  )
}

// ---------------------------------------------------------------
// helpers
// ---------------------------------------------------------------

fn fuzz_samples() -> List(BitArray) {
  let samples = [
    glessage.map([
      #(
        glessage.str("a"),
        glessage.array([glessage.uint(1), glessage.float(1.5)]),
      ),
      #(
        glessage.str("b"),
        glessage.map([#(glessage.str("c"), glessage.bool(True))]),
      ),
      #(glessage.str("d"), glessage.ext(-1, <<1, 2, 3, 4>>)),
    ]),
    glessage.array([
      glessage.str("中文"),
      glessage.uint(18_446_744_073_709_551_615),
      glessage.int(-9_223_372_036_854_775_808),
      glessage.bin(<<1, 2, 3, 4, 5>>),
    ]),
    glessage.str(string.repeat("x", 300)),
    glessage.array(list.repeat(glessage.nil(), 20)),
  ]
  list.map(samples, fn(value) {
    let assert Ok(bytes) = glessage.encode(value)
    bytes
  })
}
