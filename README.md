# QQR

QR code encoder and decoder in pure Elixir. Zero dependencies — no NIFs, no ports, no C.

## Installation

```elixir
def deps do
  [{:qqr, "~> 0.1.0"}]
end
```

## Encoding

```elixir
{:ok, matrix} = QQR.encode("Hello World")
{:ok, matrix} = QQR.encode("12345", ec_level: :high, mode: :numeric)
```

Options: `:ec_level` (`:low`, `:medium`, `:quartile`, `:high`), `:mode` (`:numeric`, `:alphanumeric`, `:byte`, `:auto`), `:version` (1–40), `:mask` (0–7). All default to auto.

### SVG

```elixir
svg = QQR.to_svg("https://example.com")
svg = QQR.to_svg("Hello", dot_shape: :rounded, color: "#336699")
```

Styling: `:dot_shape` (`:square`, `:rounded`, `:dots`, `:diamond`), `:finder_shape` (`:square`, `:rounded`, `:dots`), `:dot_size`, `:module_size`, `:quiet_zone`, `:color`, `:background`, `:logo`. See `QQR.SVG` for details.

### Phoenix LiveView

```heex
<div class="qr"><%= raw(QQR.to_svg_iodata(@url, dot_shape: :rounded)) %></div>
```

`to_svg_iodata/2` returns iodata — no extra binary copy, sent directly to the socket.

### PNG with stb_image

```elixir
{:ok, matrix} = QQR.encode("Hello World")
dim = matrix.width
scale = 10
quiet = 4
img_dim = (dim + quiet * 2) * scale

rgb =
  for y <- 0..(img_dim - 1), x <- 0..(img_dim - 1), into: <<>> do
    qr_x = div(x, scale) - quiet
    qr_y = div(y, scale) - quiet

    if QQR.BitMatrix.get(matrix, qr_x, qr_y),
      do: <<0, 0, 0>>,
      else: <<255, 255, 255>>
  end

%StbImage{data: rgb, shape: {img_dim, img_dim, 3}, type: {:u, 8}}
|> StbImage.write_file!("qr.png")
```

## Decoding

### From RGBA pixels

```elixir
case QQR.decode(rgba_binary, width, height) do
  {:ok, result} ->
    result.text     #=> "https://example.com"
    result.version  #=> 3
    result.bytes    #=> [104, 116, 116, 112, ...]
    result.chunks   #=> [%QQR.Chunk{mode: :byte, text: "https://example.com", bytes: [...]}]
    result.location #=> %QQR.Location{top_left_corner: {10.5, 10.5}, ...}

  :error ->
    # no QR code found
end
```

`rgba_binary` is a binary of RGBA pixels — 4 bytes per pixel, same format as `ImageData` in browsers.

### From a file with stb_image

```elixir
{:ok, img} = StbImage.read_file("photo.png")
{h, w, c} = img.shape

rgba =
  case c do
    4 -> img.data
    3 -> for <<r, g, b <- img.data>>, into: <<>>, do: <<r, g, b, 255>>
  end

case QQR.decode(rgba, w, h) do
  {:ok, result} -> result.text
  :error -> "no QR code found"
end
```

### From a module grid

Skip image processing when you already have a binarized grid:

```elixir
QQR.decode_matrix(bit_matrix)
```

### Inversion

By default both normal and inverted (light-on-dark) images are tried. Pass `inversion: :dont_invert` for ~2× speedup when you know the background is white.

## Features

- Versions 1–40, all error correction levels (L/M/Q/H)
- Numeric, alphanumeric, and byte encoding/decoding modes
- Kanji decoding (raw bytes — Shift-JIS to text conversion not yet implemented)
- ECI segment parsing (designators consumed, encoding not applied)
- Reed-Solomon error correction (encode and decode)
- Adaptive binarization, perspective correction
- Dark-background (inverted) and mirror/transposed QR codes
- SVG rendering with dot shapes (square, rounded, dots, diamond), finder pattern styling, and logo embedding

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
Encode: text → data bits → RS error correction → matrix → mask → QR
Decode: RGBA → binarize → locate → extract → unmask → RS correct → text
```

GF(256) exp/log tables are compiled into pattern-matched function heads. The `BitMatrix` uses a flat tuple with `:erlang.element/2` for constant-time access. No mutable state — zigzag traversal, Bresenham walks, and polynomial arithmetic are purely functional.

Encoder ported from [etiket](https://github.com/productdevbook/etiket). Decoder ported from [jsQR](https://github.com/cozmo/jsQR) with algorithm verification against [quirc](https://github.com/dlbeer/quirc).

## License

[MIT](LICENSE)
