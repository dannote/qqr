# QQR

Pure Elixir QR code decoder. No NIFs, no ports, no native dependencies.

Takes raw pixels or a pre-binarized module grid and returns the decoded text, version, error-corrected bytes, and location coordinates. Ported from [jsQR](https://github.com/cozmo/jsQR) with algorithm verification against [quirc](https://github.com/dlbeer/quirc).

## Installation

```elixir
def deps do
  [{:qqr, "~> 0.1.0"}]
end
```

## Usage

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

`rgba_binary` is a binary of RGBA pixels — 4 bytes per pixel, same layout as `ImageData` in browsers or what most image libraries produce.

### From a module grid

If you already have a binarized grid (e.g. from your own image processing), skip the binarizer:

```elixir
QQR.decode_matrix(bit_matrix)
```

### Options

```elixir
QQR.decode(rgba, w, h, inversion: :attempt_both)  # default — try normal + inverted
QQR.decode(rgba, w, h, inversion: :dont_invert)    # ~2× faster, skip dark-background codes
QQR.decode(rgba, w, h, inversion: :only_invert)    # light-on-dark only
QQR.decode(rgba, w, h, inversion: :invert_first)   # try inverted first
```

## Pipeline

```
RGBA pixels → Binarizer → Locator → Extractor → Decoder → text
```

| Stage | What it does |
|-------|-------------|
| Binarize | Adaptive threshold — RGBA to 1-bit per module |
| Locate | Find three finder patterns (1:1:3:1:1 ratio scan), alignment pattern, estimate grid size |
| Extract | Perspective transform, sample rectified module grid |
| Decode | Read format/version info, unmask, Reed-Solomon error correction, parse data segments |

## Supported features

- Versions 1–40, all four error correction levels (L/M/Q/H)
- Numeric, alphanumeric, and byte data modes
- Kanji mode (bytes only — Shift-JIS text conversion not yet implemented)
- ECI segment parsing (designators are consumed but encoding is not applied)
- Reed-Solomon error correction (Extended Euclidean Algorithm)
- Perspective correction for skewed images
- Dark-background (inverted) QR codes
- Mirror/transposed codes (automatic retry)

## Benchmarks

Compared against [qrex](https://hex.pm/packages/qrex) (Rust NIF, takes PNG). Run with `elixir bench/decode.exs`.

| Input | QQR.decode_matrix | QRex (Rust NIF) | QQR.decode (RGBA) |
|-------|------------------:|----------------:|------------------:|
| Version 1, "Hello" | **30 µs** | 51 µs | 1.5 ms |
| Version 2, URL | **55 µs** | 70 µs | 2.1 ms |
| Version 6, 100 chars | 251 µs | **146 µs** | 5.5 ms |

`decode_matrix` takes a clean module grid — no image processing. When you already have a binarized grid (e.g. from a camera pipeline or another library), pure Elixir is **1.3–1.7× faster than Rust**.

The full RGBA pipeline includes binarization, finder pattern detection, and perspective correction — currently ~37× slower. The binarizer and locator are the main bottlenecks.

## How it works

The decoder is built inside-out — the innermost layer (GF(256) arithmetic → Reed-Solomon → data parsing) was written and tested first, then wrapped with grid reading, then perspective correction, then image binarization.

GF(256) exp/log tables are generated at compile time and stored as pattern-matched function heads for O(1) lookup. The `BitMatrix` uses a flat tuple with `:erlang.element/2` for constant-time module access. No mutable state anywhere — the zigzag codeword traversal, Bresenham line walks, and polynomial arithmetic are all purely functional.

## License

[MIT](LICENSE)
