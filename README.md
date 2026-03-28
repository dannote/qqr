# QQR

QR code encoder and decoder in pure Elixir. Zero dependencies — no NIFs, no ports, no C.

## Installation

```elixir
def deps do
  [{:qqr, "~> 0.1.0"}]
end
```

## Usage

### Encoding

```elixir
{:ok, matrix} = QQR.encode("Hello World")
{:ok, matrix} = QQR.encode("12345", ec_level: :high, mode: :numeric)
```

`matrix` is a `QQR.BitMatrix` — access modules with `QQR.BitMatrix.get(matrix, x, y)`.

### From RGBA pixels

```elixir
case QQR.decode(rgba_binary, width, height) do
  {:ok, result} ->
    result.text     #=> "https://example.com"
    result.version  #=> 3
    result.bytes    #=> [104, 116, 116, 112, ...]
    result.chunks   #=> [%{mode: :byte, text: "https://example.com", bytes: [...]}]
    result.location #=> %{top_left_corner: {10.5, 10.5}, ...}

  :error ->
    # no QR code found
end
```

`rgba_binary` is a binary of RGBA pixels — 4 bytes per pixel, same format as `ImageData` in browsers or what most image libraries produce.

### From a module grid

Skip image processing when you already have a binarized grid:

```elixir
QQR.decode_matrix(bit_matrix)
```

### Inversion

By default both normal and inverted (light-on-dark) images are tried. Pass `inversion: :dont_invert` for ~2× speedup when you know the background is white.

```elixir
QQR.decode(rgba, w, h, inversion: :dont_invert)
```

## Features

- Versions 1–40, all error correction levels (L/M/Q/H)
- Numeric, alphanumeric, and byte data modes
- Kanji mode (raw bytes — Shift-JIS to text conversion not yet implemented)
- ECI segment parsing (designators consumed, encoding not applied)
- Reed-Solomon error correction
- Adaptive binarization, perspective correction
- Dark-background (inverted) and mirror/transposed QR codes

## Benchmarks

Compared against [qrex](https://hex.pm/packages/qrex) (Rust NIF, PNG input). Run with `elixir bench/decode.exs`.

| Input | QQR.decode_matrix | QRex (Rust NIF) | QQR.decode (RGBA) |
|-------|------------------:|----------------:|------------------:|
| Version 1, "Hello" | **30 µs** | 51 µs | 1.5 ms |
| Version 2, URL | **55 µs** | 70 µs | 2.1 ms |
| Version 6, 100 chars | 251 µs | **146 µs** | 5.5 ms |

Grid-only decode (`decode_matrix`) is **1.3–1.7× faster than Rust** for small and medium QR codes. The full RGBA pipeline is slower due to image processing overhead in the binarizer and locator.

## How it works

```
RGBA pixels → Binarizer → Locator → Extractor → Decoder → text
```

| Stage | What it does |
|-------|-------------|
| Binarize | Adaptive threshold — RGBA to 1-bit per module |
| Locate | Find three finder patterns (1:1:3:1:1 ratio scan), alignment pattern, grid size |
| Extract | Perspective transform, sample rectified module grid |
| Decode | Format/version info, unmask, Reed-Solomon error correction, data segment parsing |

GF(256) exp/log tables are compiled into pattern-matched function heads. The `BitMatrix` uses a flat tuple with `:erlang.element/2` for constant-time access. No mutable state — zigzag traversal, Bresenham walks, and polynomial arithmetic are purely functional.

Ported from [jsQR](https://github.com/cozmo/jsQR) with algorithm verification against [quirc](https://github.com/dlbeer/quirc).

## License

[MIT](LICENSE)
