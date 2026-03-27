# QQR

Pure Elixir QR code decoder. No NIFs, no ports, no external dependencies.

Locates, extracts, and decodes QR codes from images or raw module grids.

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
    result.text     # "Hello World"
    result.version  # 2
    result.bytes    # [72, 101, 108, ...]
    result.chunks   # [%{mode: :byte, text: "Hello World", bytes: [...]}]
    result.location # finder pattern and corner coordinates

  :error ->
    # no QR code found
end
```

### From a BitMatrix (pre-binarized grid)

```elixir
QQR.decode_matrix(bit_matrix)
```

### Options

```elixir
QQR.decode(rgba, w, h, inversion: :attempt_both)  # default — try normal + inverted
QQR.decode(rgba, w, h, inversion: :dont_invert)    # ~2x faster, skip dark-background QR
QQR.decode(rgba, w, h, inversion: :only_invert)    # only try inverted
QQR.decode(rgba, w, h, inversion: :invert_first)   # try inverted first, then normal
```

## Pipeline

```
RGBA pixels → Binarizer → Locator → Extractor → Decoder → text
```

| Stage | Module | What it does |
|-------|--------|-------------|
| Binarize | `QQR.Binarizer` | Adaptive threshold, RGBA → 1-bit grid |
| Locate | `QQR.Locator` | Find 3 finder patterns, alignment pattern, estimate grid size |
| Extract | `QQR.Extractor` | Perspective transform, sample clean module grid |
| Decode | `QQR.Decoder` | Format info, unmask, Reed-Solomon, parse data |

## Supported features

- QR versions 1–40
- Error correction levels L, M, Q, H
- Numeric, alphanumeric, byte, kanji modes
- ECI indicators
- Reed-Solomon error correction
- Perspective correction for skewed images
- Dark-background (inverted) QR codes
- Mirror/transposed QR codes (auto-retry)

## License

Apache-2.0
