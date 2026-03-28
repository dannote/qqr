defmodule QQR.Encoder.Format do
  @moduledoc false

  import Bitwise

  @format_generator 0x537
  @format_mask 0x5412

  @ec_level_bits %{low: 0b01, medium: 0b00, quartile: 0b11, high: 0b10}

  def generate_format_info(ec_level, mask) do
    data = Map.fetch!(@ec_level_bits, ec_level) <<< 3 ||| mask
    bch = bch_encode(data, 10, @format_generator)
    bxor(data <<< 10 ||| bch, @format_mask)
  end

  def write_format_info(matrix, ec_level, mask, size) do
    info = generate_format_info(ec_level, mask)
    bits = for i <- 14..0//-1, do: (info >>> i &&& 1) == 1

    matrix
    |> write_format_top_left(bits, size)
    |> write_format_other(bits, size)
  end

  def write_version_info(matrix, version, _size) when version < 7, do: matrix

  def write_version_info(matrix, version, size) do
    info = QQR.Version.info_bits(version)

    for i <- 0..17, reduce: matrix do
      acc ->
        bit = (info >>> i &&& 1) == 1
        row = div(i, 3)
        col = rem(i, 3)

        acc
        |> Map.put({row, size - 11 + col}, bit)
        |> Map.put({size - 11 + col, row}, bit)
    end
  end

  defp write_format_top_left(matrix, bits, _size) do
    # Along row 8 (left side): columns 0-5, skip 6, columns 7-8
    # Along column 8 (top side): rows 7-5 (skip 6), rows 4-0
    positions_row8 = [
      {8, 0},
      {8, 1},
      {8, 2},
      {8, 3},
      {8, 4},
      {8, 5},
      {8, 7},
      {8, 8}
    ]

    positions_col8 = [
      {7, 8},
      {5, 8},
      {4, 8},
      {3, 8},
      {2, 8},
      {1, 8},
      {0, 8}
    ]

    all_positions = positions_row8 ++ positions_col8

    all_positions
    |> Enum.zip(bits)
    |> Enum.reduce(matrix, fn {{row, col}, bit}, acc ->
      Map.put(acc, {row, col}, bit)
    end)
  end

  defp write_format_other(matrix, bits, size) do
    # Along column 8 (bottom): rows size-1 down to size-7
    positions_bottom =
      for i <- 0..6, do: {size - 1 - i, 8}

    # Along row 8 (right): columns size-8 to size-1
    positions_right =
      for i <- 0..7, do: {8, size - 8 + i}

    all_positions = positions_bottom ++ positions_right

    all_positions
    |> Enum.zip(bits)
    |> Enum.reduce(matrix, fn {{row, col}, bit}, acc ->
      Map.put(acc, {row, col}, bit)
    end)
  end

  defp bch_encode(data, total_bits, generator) do
    gen_bits = bit_length(generator)
    shifted = data <<< total_bits

    Enum.reduce((total_bits + gen_bits - 2)..total_bits//-1, shifted, fn _bit, remainder ->
      if bit_length(remainder) >= gen_bits do
        bxor(remainder, generator <<< (bit_length(remainder) - gen_bits))
      else
        remainder
      end
    end)
    |> band((1 <<< total_bits) - 1)
  end

  defp bit_length(0), do: 0
  defp bit_length(n), do: do_bit_length(n, 0)

  defp do_bit_length(0, acc), do: acc
  defp do_bit_length(n, acc), do: do_bit_length(n >>> 1, acc + 1)
end
