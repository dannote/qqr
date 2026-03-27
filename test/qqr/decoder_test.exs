defmodule QQR.DecoderTest do
  use ExUnit.Case, async: true

  alias QQR.BitMatrix
  alias QQR.Decoder

  defp matrix_from_string(str) do
    rows =
      str
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)

    height = length(rows)
    width = String.length(hd(rows))

    data =
      Enum.flat_map(rows, fn row ->
        row
        |> String.graphemes()
        |> Enum.map(fn
          "#" -> 1
          "." -> 0
        end)
      end)

    BitMatrix.from_list(width, height, data)
  end

  # Version 1-M, mask 0, numeric mode encoding "01234567"
  # Generated with Python qrcode library
  @v1_m_numeric """
  #######...###.#######
  #.....#.###...#.....#
  #.###.#..##...#.###.#
  #.###.#..#.##.#.###.#
  #.###.#.##.##.#.###.#
  #.....#....#..#.....#
  #######.#.#.#.#######
  .....................
  #.#.#.#...#.#...#..#.
  ##.#....#.##.#.#...#.
  ...##.###.##.###.###.
  ##..##.#.#.###.##..#.
  ..#..###.###.###....#
  ........#.#...#....#.
  #######.....#...#...#
  #.....#...#...#..#.##
  #.###.#.###.#.#.###.#
  #.###.#..#.#.#.#.###.
  #.###.#.##.#.###..#.#
  #.....#....###.###...
  #######.#..#.###..#.#
  """

  describe "decode/1" do
    test "decodes Version 1-M numeric QR code" do
      matrix = matrix_from_string(@v1_m_numeric)
      assert {:ok, result} = Decoder.decode(matrix)
      assert result.text == "01234567"
      assert result.version == 1
      assert hd(result.chunks).mode == :numeric
    end

    test "returns :error for nil input" do
      assert :error = Decoder.decode(nil)
    end

    test "returns :error for random noise matrix" do
      data = for _ <- 1..(21 * 21), do: Enum.random([0, 1])
      :rand.seed(:exsss, {0, 0, 0})
      matrix = BitMatrix.from_list(21, 21, data)
      assert :error = Decoder.decode(matrix)
    end

    test "mirror retry decodes transposed QR code" do
      matrix = matrix_from_string(@v1_m_numeric)

      # Transpose the matrix (swap x,y)
      transposed =
        Enum.reduce(0..20, BitMatrix.new(21, 21), fn x, acc ->
          Enum.reduce(0..20, acc, fn y, acc2 ->
            BitMatrix.set(acc2, y, x, BitMatrix.get(matrix, x, y))
          end)
        end)

      # The normal decode of a transposed QR will fail, but the mirror retry should succeed
      assert {:ok, result} = Decoder.decode(transposed)
      assert result.text == "01234567"
    end
  end
end
