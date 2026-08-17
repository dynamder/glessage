# glessage

A pure Gleam [MessagePack](https://msgpack.org) encoder and decoder with **no
native code**: everything is built on Gleam bit syntax, so the only dependency
is `gleam_stdlib`. Works on any Gleam target (Erlang, JavaScript, ...).

```sh
gleam add glessage
```

## Usage

```gleam
import glessage

pub fn main() {
  // Build a value with the constructor helpers
  let value = glessage.map([
    #(glessage.str("op"), glessage.str("hello")),
    #(glessage.str("version"), glessage.uint(1)),
  ])

  // Encode to bytes
  let assert Ok(bytes) = glessage.encode(value)

  // Decode exactly one value (fails on trailing bytes)
  let assert Ok(decoded) = glessage.decode_one(bytes)

  // Or decode in a streaming fashion, keeping the remaining bytes
  let assert Ok(#(first, rest)) = glessage.decode(bytes)
}
```

## Examples

Runnable examples live in `src/glessage/example/`; see
[docs/examples.md](./docs/examples.md) for details. Gleam has no built-in
examples mechanism, so each example is a normal module with a `pub fn main`
run via `gleam run -m`:

```sh
gleam run -m glessage/example/basic
```

## Module layout

- `glessage` — public API: constructor functions (`glessage.str(...)`,
  `glessage.uint(...)`, ...), `encode`, `decode`, `decode_one`
- `glessage/types` — the value model (`MsgValue`) and error types. Import this
  module to pattern match on values:

  ```gleam
  import glessage
  import glessage/types

  case value {
    types.Map(entries) -> // ...
    types.UInt(n) -> // ...
    _ -> // ...
  }
  ```

- `glessage/internal/*` — encoder/decoder implementations (package-internal)

## Supported types

| MessagePack               | glessage                                | decoded as |
| ------------------------- | --------------------------------------- | ---------- |
| `nil`                     | `glessage.nil()`                        | `Nil`      |
| `true` / `false`          | `glessage.bool(True)`                   | `Bool`     |
| positive fixint, `uint8..64` | `glessage.uint(n)`                   | `UInt`     |
| negative fixint, `int8..64`  | `glessage.int(n)`                    | `Int`      |
| `float64` (encode), `float32`/`float64` (decode) | `glessage.float(f)` | `Float` |
| `fixstr`, `str8..32`       | `glessage.str(s)`                       | `Str`      |
| `bin8..32`                 | `glessage.bin(bits)`                    | `Bin`      |
| `fixarray`, `array16..32`  | `glessage.array(items)`                 | `Array`    |
| `fixmap`, `map16..32`      | `glessage.map(entries)`                 | `Map`      |
| `fixext1..16`, `ext8..32`  | `glessage.ext(kind, data)`              | `Ext`      |

Notes:

- Non-negative `Int` values are encoded in their minimal unsigned form
  (positive fixint / `uint8..64`) and decode back as `UInt`.
- Floats are always encoded as `float64`; `float32` input is accepted on
  decode and promoted to `float64`.
- Extension values are handled as **opaque data** — the kind is a signed 8-bit
  integer (`-128 .. 127`) and no timestamp or other semantics are applied
  (the predefined timestamp type `-1` passes through unchanged).
- The wire format follows the [MessagePack specification](https://github.com/msgpack/msgpack/blob/master/spec.md);
  see [SPEC_COMPLIANCE.md](./SPEC_COMPLIANCE.md) for the detailed audit.

## Development

```sh
gleam test    # golden bytes + round trips + error paths + fuzz (deterministic)
gleam format  # format the code
```
