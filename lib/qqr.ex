defmodule QQR do
  @moduledoc """
  Pure Elixir QR code decoder.

  ## From RGBA pixels

      case QQR.decode(rgba_binary, width, height) do
        {:ok, result} ->
          result.text     #=> "https://example.com"
          result.version  #=> 3
          result.location #=> %{top_left_corner: {10.5, 10.5}, ...}

        :error ->
          :no_qr_found
      end

  `rgba_binary` is a binary of RGBA pixels — 4 bytes per pixel, same layout
  as `ImageData` in browsers or what most image libraries produce.

  ## From a module grid

  If you already have a binarized grid, skip the binarizer:

      QQR.decode_matrix(bit_matrix)

  ## Inversion

  By default both normal and inverted (light-on-dark) images are tried.
  Pass `inversion: :dont_invert` for ~2× speedup when you know the
  background is white.
  """

  alias QQR.{Binarizer, Decoder, Extractor, Locator}

  @type result :: %{
          text: String.t(),
          bytes: [non_neg_integer()],
          chunks: [map()],
          version: pos_integer(),
          location: location()
        }

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

  @type option :: {:inversion, :dont_invert | :only_invert | :attempt_both | :invert_first}

  @doc """
  Decode a QR code from raw RGBA pixel data.

  Returns `{:ok, result}` with decoded text, bytes, chunks, version, and
  location coordinates, or `:error` if no valid QR code is found.

  ## Options

    * `:inversion` — `:attempt_both` (default), `:dont_invert`, `:only_invert`,
      or `:invert_first`

  """
  @spec decode(binary(), pos_integer(), pos_integer(), [option()]) :: {:ok, result()} | :error
  def decode(rgba, width, height, opts \\ []) do
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
  clean, rectified grid of modules (as produced by `QQR.Extractor` or an
  external QR encoder library).
  """
  @spec decode_matrix(QQR.BitMatrix.t()) :: {:ok, map()} | :error
  def decode_matrix(matrix), do: Decoder.decode(matrix)

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
