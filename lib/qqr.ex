defmodule QQR do
  @moduledoc """
  Pure Elixir QR code decoder.

  ## Usage

      case QQR.decode(rgba_pixels, width, height) do
        {:ok, result} ->
          IO.puts(result.text)
        :error ->
          IO.puts("No QR code found")
      end
  """

  alias QQR.{Binarizer, Locator, Extractor, Decoder}

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

  @spec decode_matrix(QQR.BitMatrix.t()) :: {:ok, map()} | :error
  def decode_matrix(matrix), do: Decoder.decode(matrix)

  defp scan(nil), do: :error

  defp scan(matrix) do
    case Locator.locate(matrix) do
      nil ->
        :error

      locations ->
        Enum.find_value(locations, :error, fn location ->
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
        end)
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
