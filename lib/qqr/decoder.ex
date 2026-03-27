defmodule QQR.Decoder do
  @moduledoc false

  import Bitwise

  alias QQR.BitMatrix
  alias QQR.DataDecoder
  alias QQR.ReedSolomon
  alias QQR.Version

  @format_info_table [
    {0x5412, {1, 0}}, {0x5125, {1, 1}}, {0x5E7C, {1, 2}}, {0x5B4B, {1, 3}},
    {0x45F9, {1, 4}}, {0x40CE, {1, 5}}, {0x4F97, {1, 6}}, {0x4AA0, {1, 7}},
    {0x77C4, {0, 0}}, {0x72F3, {0, 1}}, {0x7DAA, {0, 2}}, {0x789D, {0, 3}},
    {0x662F, {0, 4}}, {0x6318, {0, 5}}, {0x6C41, {0, 6}}, {0x6976, {0, 7}},
    {0x1689, {3, 0}}, {0x13BE, {3, 1}}, {0x1CE7, {3, 2}}, {0x19D0, {3, 3}},
    {0x0762, {3, 4}}, {0x0255, {3, 5}}, {0x0D0C, {3, 6}}, {0x083B, {3, 7}},
    {0x355F, {2, 0}}, {0x3068, {2, 1}}, {0x3F31, {2, 2}}, {0x3A06, {2, 3}},
    {0x24B4, {2, 4}}, {0x2183, {2, 5}}, {0x2EDA, {2, 6}}, {0x2BED, {2, 7}}
  ]

  @spec decode(BitMatrix.t() | nil) :: {:ok, map()} | :error
  def decode(nil), do: :error

  def decode(%BitMatrix{} = matrix) do
    case decode_matrix(matrix) do
      {:ok, _} = result ->
        result

      :error ->
        matrix
        |> mirror()
        |> decode_matrix()
    end
  end

  defp mirror(%BitMatrix{width: w, height: h} = matrix) do
    for x <- 0..(w - 1), y <- (x + 1)..(h - 1)//1, reduce: matrix do
      acc ->
        a = BitMatrix.get(acc, x, y)
        b = BitMatrix.get(acc, y, x)

        if a != b do
          acc
          |> BitMatrix.set(x, y, b)
          |> BitMatrix.set(y, x, a)
        else
          acc
        end
    end
  end

  defp decode_matrix(%BitMatrix{} = matrix) do
    with {:ok, version} <- read_version(matrix),
         {:ok, {ec_level, data_mask}} <- read_format_information(matrix),
         codewords = read_codewords(matrix, version, data_mask),
         {:ok, data_blocks} <- get_data_blocks(codewords, version, ec_level),
         {:ok, result_bytes} <- rs_correct_blocks(data_blocks),
         {:ok, result} <- DataDecoder.decode(result_bytes, version.number) do
      {:ok, result}
    else
      _ -> :error
    end
  end

  defp rs_correct_blocks(data_blocks) do
    Enum.reduce_while(data_blocks, {:ok, []}, fn {num_data, codewords}, {:ok, acc} ->
      case ReedSolomon.decode(codewords, length(codewords) - num_data) do
        {:ok, corrected} ->
          {:cont, {:ok, acc ++ Enum.take(corrected, num_data)}}

        :error ->
          {:halt, :error}
      end
    end)
  end

  defp read_version(%BitMatrix{height: dimension} = matrix) do
    provisional = div(dimension - 17, 4)

    if provisional <= 6 do
      {:ok, Version.get(provisional)}
    else
      top_right_bits =
        for y <- 5..0//-1, x <- (dimension - 9)..(dimension - 11)//-1, reduce: 0 do
          acc -> push_bit(BitMatrix.get(matrix, x, y), acc)
        end

      bottom_left_bits =
        for x <- 5..0//-1, y <- (dimension - 9)..(dimension - 11)//-1, reduce: 0 do
          acc -> push_bit(BitMatrix.get(matrix, x, y), acc)
        end

      find_best_version(top_right_bits, bottom_left_bits)
    end
  end

  defp find_best_version(top_right_bits, bottom_left_bits) do
    {best_version, best_diff} =
      Enum.reduce(7..40, {nil, :infinity}, fn n, {_best_v, best_d} = best ->
        v = Version.get(n)

        if v.info_bits == top_right_bits or v.info_bits == bottom_left_bits do
          {v, 0}
        else
          d1 = num_bits_differing(top_right_bits, v.info_bits)
          d2 = num_bits_differing(bottom_left_bits, v.info_bits)
          min_d = min(d1, d2)

          if min_d < best_d, do: {v, min_d}, else: best
        end
      end)

    if best_diff <= 3, do: {:ok, best_version}, else: :error
  end

  defp read_format_information(%BitMatrix{height: dimension} = matrix) do
    top_left_bits =
      for x <- 0..8, x != 6, reduce: 0 do
        acc -> push_bit(BitMatrix.get(matrix, x, 8), acc)
      end

    top_left_bits =
      for y <- 7..0//-1, y != 6, reduce: top_left_bits do
        acc -> push_bit(BitMatrix.get(matrix, 8, y), acc)
      end

    bottom_right_bits =
      for y <- (dimension - 1)..(dimension - 7)//-1, reduce: 0 do
        acc -> push_bit(BitMatrix.get(matrix, 8, y), acc)
      end

    bottom_right_bits =
      for x <- (dimension - 8)..(dimension - 1), reduce: bottom_right_bits do
        acc -> push_bit(BitMatrix.get(matrix, x, 8), acc)
      end

    find_best_format(top_left_bits, bottom_right_bits)
  end

  defp find_best_format(bits1, bits2) do
    {best_info, best_diff} =
      Enum.reduce(@format_info_table, {nil, :infinity}, fn {code, format_info}, {best_fi, best_d} ->
        cond do
          code == bits1 or code == bits2 ->
            {format_info, 0}

          true ->
            d1 = num_bits_differing(bits1, code)
            {fi2, d2} = if d1 < best_d, do: {format_info, d1}, else: {best_fi, best_d}

            if bits1 != bits2 do
              d3 = num_bits_differing(bits2, code)
              if d3 < d2, do: {format_info, d3}, else: {fi2, d2}
            else
              {fi2, d2}
            end
        end
      end)

    if best_diff <= 3, do: {:ok, best_info}, else: :error
  end

  defp build_function_pattern_mask(%Version{} = version) do
    dimension = Version.dimension(version)

    BitMatrix.new(dimension, dimension)
    |> BitMatrix.set_region(0, 0, 9, 9, true)
    |> BitMatrix.set_region(dimension - 8, 0, 8, 9, true)
    |> BitMatrix.set_region(0, dimension - 8, 9, 8, true)
    |> set_alignment_patterns(version, dimension)
    |> BitMatrix.set_region(6, 9, 1, dimension - 17, true)
    |> BitMatrix.set_region(9, 6, dimension - 17, 1, true)
    |> maybe_set_version_info(version, dimension)
  end

  defp set_alignment_patterns(matrix, %Version{alignment_pattern_centers: centers}, dimension) do
    for x <- centers, y <- centers, reduce: matrix do
      acc ->
        if (x == 6 and y == 6) or
             (x == 6 and y == dimension - 7) or
             (x == dimension - 7 and y == 6) do
          acc
        else
          BitMatrix.set_region(acc, x - 2, y - 2, 5, 5, true)
        end
    end
  end

  defp maybe_set_version_info(matrix, %Version{number: n}, dimension) when n > 6 do
    matrix
    |> BitMatrix.set_region(dimension - 11, 0, 3, 6, true)
    |> BitMatrix.set_region(0, dimension - 11, 6, 3, true)
  end

  defp maybe_set_version_info(matrix, _, _), do: matrix

  defp read_codewords(%BitMatrix{height: dimension} = matrix, version, data_mask) do
    function_mask = build_function_pattern_mask(version)

    {codewords, _byte, _bits} =
      zigzag_traverse(dimension, matrix, function_mask, data_mask)

    Enum.reverse(codewords)
  end

  defp zigzag_traverse(dimension, matrix, function_mask, data_mask) do
    col_pairs = build_column_pairs(dimension)

    Enum.reduce(col_pairs, {[], 0, 0}, fn {col_index, reading_up}, {words, current_byte, bits_read} ->
      rows = if reading_up, do: (dimension - 1)..0//-1, else: 0..(dimension - 1)

      Enum.reduce(rows, {words, current_byte, bits_read}, fn y, acc ->
        Enum.reduce(0..1, acc, fn col_offset, {w, byte, br} ->
          x = col_index - col_offset

          if BitMatrix.get(function_mask, x, y) do
            {w, byte, br}
          else
            bit = BitMatrix.get(matrix, x, y)
            bit = if data_mask_applies?(data_mask, x, y), do: !bit, else: bit
            byte = push_bit(bit, byte)
            br = br + 1

            if br == 8 do
              {[byte | w], 0, 0}
            else
              {w, byte, br}
            end
          end
        end)
      end)
    end)
  end

  defp build_column_pairs(dimension) do
    do_build_cols(dimension - 1, true, [])
  end

  defp do_build_cols(col, _reading_up, acc) when col <= 0, do: Enum.reverse(acc)

  defp do_build_cols(col, reading_up, acc) do
    col = if col == 6, do: col - 1, else: col
    do_build_cols(col - 2, !reading_up, [{col, reading_up} | acc])
  end

  defp data_mask_applies?(0, x, y), do: rem(y + x, 2) == 0
  defp data_mask_applies?(1, _x, y), do: rem(y, 2) == 0
  defp data_mask_applies?(2, x, _y), do: rem(x, 3) == 0
  defp data_mask_applies?(3, x, y), do: rem(y + x, 3) == 0
  defp data_mask_applies?(4, x, y), do: rem(div(y, 2) + div(x, 3), 2) == 0
  defp data_mask_applies?(5, x, y), do: rem(x * y, 2) + rem(x * y, 3) == 0
  defp data_mask_applies?(6, x, y), do: rem(rem(y * x, 2) + rem(y * x, 3), 2) == 0
  defp data_mask_applies?(7, x, y), do: rem(rem(y + x, 2) + rem(y * x, 3), 2) == 0

  defp get_data_blocks(codewords, %Version{} = version, ec_level) do
    %Version.ECLevel{ec_codewords_per_block: ec_per_block, ec_blocks: ec_blocks} =
      Enum.at(version.error_correction_levels, ec_level)

    blocks =
      Enum.flat_map(ec_blocks, fn {num_blocks, data_per_block} ->
        List.duplicate(data_per_block, num_blocks)
      end)

    total_codewords = Enum.sum(blocks) + length(blocks) * ec_per_block

    if length(codewords) < total_codewords do
      :error
    else
      codewords = Enum.take(codewords, total_codewords)
      {:ok, distribute_codewords(codewords, blocks, ec_per_block)}
    end
  end

  defp distribute_codewords(codewords, blocks, ec_per_block) do
    num_blocks = length(blocks)
    short_data_size = Enum.min(blocks)

    block_data = List.duplicate([], num_blocks)

    {block_data, codewords} =
      if short_data_size > 0 do
        Enum.reduce(1..short_data_size, {block_data, codewords}, fn _i, {bd, cw} ->
          round_robin_one(bd, cw, num_blocks)
        end)
      else
        {block_data, codewords}
      end

    {block_data, codewords} =
      Enum.reduce(0..(num_blocks - 1), {block_data, codewords}, fn idx, {bd, cw} ->
        if Enum.at(blocks, idx) > short_data_size do
          [h | rest] = cw
          {List.update_at(bd, idx, &(&1 ++ [h])), rest}
        else
          {bd, cw}
        end
      end)

    {block_data, _} =
      if ec_per_block > 0 do
        Enum.reduce(1..ec_per_block, {block_data, codewords}, fn _i, {bd, cw} ->
          round_robin_one(bd, cw, num_blocks)
        end)
      else
        {block_data, codewords}
      end

    Enum.zip(blocks, block_data)
    |> Enum.map(fn {data_size, cw} -> {data_size, cw} end)
  end

  defp round_robin_one(block_data, codewords, num_blocks) do
    Enum.reduce(0..(num_blocks - 1), {block_data, codewords}, fn idx, {bd, [h | rest]} ->
      {List.update_at(bd, idx, &(&1 ++ [h])), rest}
    end)
  end

  defp push_bit(true, byte), do: bsl(byte, 1) ||| 1
  defp push_bit(false, byte), do: bsl(byte, 1)

  defp num_bits_differing(x, y) do
    z = bxor(x, y)
    popcount(z, 0)
  end

  defp popcount(0, count), do: count
  defp popcount(z, count), do: popcount(band(z, z - 1), count + 1)
end
