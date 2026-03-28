defmodule QQR do
  @moduledoc """
  Pure Elixir QR code encoder and decoder.

  ## Encoding

      {:ok, matrix} = QQR.encode("Hello World")
      svg_string = QQR.to_svg("https://example.com")

  ## Decoding

      {:ok, result} = QQR.decode(rgba_binary, width, height)
      result.text  #=> "https://example.com"

  ## SVG rendering

  `to_svg/2` is the most common way to use the encoder — it encodes
  and renders in one call. For Phoenix LiveView, use `to_svg_iodata/2`
  to avoid an extra binary copy:

      raw(QQR.to_svg_iodata("https://example.com"))

  See `QQR.SVG` for all styling options (dot shapes, finder patterns, logos).
  """

  alias QQR.{Binarizer, BitMatrix, Decoder, Extractor, Locator, Result, SVG}

  @type location :: %{
          top_left_corner: point(),
          top_right_corner: point(),
          bottom_left_corner: point(),
          bottom_right_corner: point(),
          top_left_finder: point(),
          top_right_finder: point(),
          bottom_left_finder: point(),
          alignment: point() | nil
        }

  @type point :: {number(), number()}

  @type encode_option ::
          {:ec_level, :low | :medium | :quartile | :high}
          | {:mode, :numeric | :alphanumeric | :byte | :auto}
          | {:version, 1..40}
          | {:mask, 0..7}

  @type decode_option ::
          {:inversion, :dont_invert | :only_invert | :attempt_both | :invert_first}

  # -- Encoding --

  @doc """
  Encode text as a QR code matrix.

  ## Options

    * `:ec_level` — `:low`, `:medium` (default), `:quartile`, or `:high`
    * `:mode` — `:numeric`, `:alphanumeric`, `:byte`, or `:auto` (default)
    * `:version` — 1–40, auto-selected if omitted
    * `:mask` — 0–7, auto-selected if omitted

  """
  @spec encode(String.t(), [encode_option()]) :: {:ok, BitMatrix.t()} | {:error, String.t()}
  def encode(text, opts \\ []) do
    validate_encode_opts!(opts)
    QQR.Encoder.encode(text, opts)
  end

  @doc """
  Encode text and render as an SVG string.

  Accepts all `encode/2` options plus SVG options (see `QQR.SVG`):

    * `:dot_shape` — `:square`, `:rounded`, `:dots`, or `:diamond`
    * `:finder_shape` — `:square`, `:rounded`, or `:dots`
    * `:module_size`, `:quiet_zone`, `:color`, `:background`
    * `:dot_size`, `:logo`

  ## Examples

      svg = QQR.to_svg("https://example.com")
      svg = QQR.to_svg("Hello", dot_shape: :rounded, color: "#336699")

  """
  @spec to_svg(String.t(), keyword()) :: String.t()
  def to_svg(text, opts \\ []) do
    IO.iodata_to_binary(to_svg_iodata(text, opts))
  end

  @doc """
  Encode text and render as SVG iodata.

  Same as `to_svg/2` but returns iodata instead of a string — avoids
  an extra binary copy. Useful in Phoenix templates:

      <div class="qr"><%= raw(QQR.to_svg_iodata(@url)) %></div>

  Raises on encode failure. Accepts same options as `to_svg/2`.
  """
  @spec to_svg_iodata(String.t(), keyword()) :: iodata()
  def to_svg_iodata(text, opts \\ []) do
    {encode_opts, svg_opts} = split_opts(opts)
    validate_encode_opts!(encode_opts)

    case encode(text, encode_opts) do
      {:ok, matrix} -> SVG.to_iodata(matrix, svg_opts)
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # -- Decoding --

  @doc """
  Decode a QR code from raw RGBA pixel data.

  `rgba` is a binary of 4 bytes per pixel (R, G, B, A), same format as
  `ImageData` in browsers or what most image libraries produce.

  ## Options

    * `:inversion` — `:attempt_both` (default), `:dont_invert`, `:only_invert`,
      or `:invert_first`

  """
  @spec decode(binary(), pos_integer(), pos_integer(), [decode_option()]) ::
          {:ok, Result.t()} | :error
  def decode(rgba, width, height, opts \\ [])
      when is_binary(rgba) and is_integer(width) and is_integer(height) do
    validate_decode_opts!(opts)
    validate_decode_args!(rgba, width, height)
    inversion = Keyword.get(opts, :inversion, :attempt_both)

    should_invert = inversion in [:attempt_both, :invert_first]
    try_inverted_first = inversion in [:only_invert, :invert_first]

    {binarized, inverted} = Binarizer.binarize(rgba, width, height, invert: should_invert)

    first = if try_inverted_first, do: inverted, else: binarized
    second = if try_inverted_first, do: binarized, else: inverted

    case scan(first) do
      {:ok, _} = result ->
        result

      :error ->
        if inversion in [:attempt_both, :invert_first] and second do
          scan(second)
        else
          :error
        end
    end
  end

  @doc """
  Decode a QR code from a pre-binarized module grid.

  Skips binarization and finder pattern detection — the matrix must be a
  clean, rectified grid of modules (e.g. from a QR encoder library).
  """
  @spec decode_matrix(QQR.BitMatrix.t()) :: {:ok, Result.t()} | :error
  def decode_matrix(matrix), do: Decoder.decode(matrix)

  # -- Private --

  @encode_keys [:ec_level, :mode, :version, :mask]

  defp validate_encode_opts!(opts) do
    Enum.each(opts, fn
      {:ec_level, v} when v in [:low, :medium, :quartile, :high] -> :ok
      {:mode, v} when v in [:numeric, :alphanumeric, :byte, :auto] -> :ok
      {:version, v} when is_integer(v) and v >= 1 and v <= 40 -> :ok
      {:mask, v} when is_integer(v) and v >= 0 and v <= 7 -> :ok
      {k, v} -> raise ArgumentError, "invalid encode option: #{inspect({k, v})}"
    end)
  end

  defp validate_decode_opts!(opts) do
    Enum.each(opts, fn
      {:inversion, v} when v in [:dont_invert, :only_invert, :attempt_both, :invert_first] -> :ok
      {k, v} -> raise ArgumentError, "invalid decode option: #{inspect({k, v})}"
    end)
  end

  defp split_opts(opts) do
    Enum.split_with(opts, fn {k, _} -> k in @encode_keys end)
  end

  defp scan(nil), do: :error

  defp scan(matrix) do
    case Locator.locate(matrix) do
      nil ->
        :error

      locations ->
        Enum.find_value(locations, :error, &try_decode_location(matrix, &1))
    end
  end

  defp try_decode_location(matrix, location) do
    extractor_location = %{
      top_left: location.top_left,
      top_right: location.top_right,
      bottom_left: location.bottom_left,
      alignment_pattern: location.alignment,
      dimension: location.dimension
    }

    {extracted, mapping_fn} = Extractor.extract(matrix, extractor_location)

    case Decoder.decode(extracted) do
      {:ok, decoded} ->
        {:ok, Map.put(decoded, :location, build_location(location, mapping_fn))}

      :error ->
        nil
    end
  end

  defp validate_decode_args!(_rgba, width, height) when width <= 0 or height <= 0 do
    raise ArgumentError, "width and height must be positive, got: #{width}x#{height}"
  end

  defp validate_decode_args!(rgba, width, height) do
    expected = width * height * 4
    actual = byte_size(rgba)

    if actual != expected do
      raise ArgumentError,
            "expected #{expected} bytes for #{width}x#{height} RGBA image, got: #{actual}"
    end
  end

  defp build_location(location, mapping_fn) do
    dim = location.dimension

    %{
      top_left_corner: mapping_fn.(0, 0),
      top_right_corner: mapping_fn.(dim, 0),
      bottom_left_corner: mapping_fn.(0, dim),
      bottom_right_corner: mapping_fn.(dim, dim),
      top_left_finder: location.top_left,
      top_right_finder: location.top_right,
      bottom_left_finder: location.bottom_left,
      alignment: location.alignment
    }
  end
end
