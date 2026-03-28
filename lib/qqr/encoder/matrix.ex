defmodule QQR.Encoder.Matrix do
  @moduledoc false

  alias QQR.BitMatrix

  @dark_module_row_offset 9

  def build(version, bits) do
    size = QQR.Version.dimension(version)
    matrix = %{}

    matrix
    |> place_finder_patterns(size)
    |> place_separators(size)
    |> place_timing_patterns(size)
    |> place_alignment_patterns(version, size)
    |> place_dark_module(version)
    |> reserve_format_areas(size)
    |> reserve_version_areas(version, size)
    |> place_data(bits, size, version)
  end

  def to_bit_matrix(matrix, size) do
    Enum.reduce(matrix, BitMatrix.new(size, size), fn {{row, col}, val}, bm ->
      BitMatrix.set(bm, col, row, val)
    end)
  end

  def place_finder_patterns(matrix, size) do
    matrix
    |> place_finder_pattern(0, 0)
    |> place_finder_pattern(size - 7, 0)
    |> place_finder_pattern(0, size - 7)
  end

  defp place_finder_pattern(matrix, start_row, start_col) do
    pattern = [
      [1, 1, 1, 1, 1, 1, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 0, 1, 1, 1, 0, 1],
      [1, 0, 1, 1, 1, 0, 1],
      [1, 0, 1, 1, 1, 0, 1],
      [1, 0, 0, 0, 0, 0, 1],
      [1, 1, 1, 1, 1, 1, 1]
    ]

    pattern
    |> Enum.with_index()
    |> Enum.reduce(matrix, fn {row_data, r}, acc ->
      row_data
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {val, c}, acc2 ->
        Map.put(acc2, {start_row + r, start_col + c}, val == 1)
      end)
    end)
  end

  defp place_separators(matrix, size) do
    matrix
    |> place_separator_h(7, 0, 8)
    |> place_separator_h(7, size - 8, 8)
    |> place_separator_h(size - 8, 0, 8)
    |> place_separator_v(0, 7, 7)
    |> place_separator_v(0, size - 8, 7)
    |> place_separator_v(size - 7, 7, 7)
  end

  defp place_separator_h(matrix, row, col, len) do
    Enum.reduce(0..(len - 1), matrix, fn c, acc ->
      Map.put(acc, {row, col + c}, false)
    end)
  end

  defp place_separator_v(matrix, row, col, len) do
    Enum.reduce(0..(len - 1), matrix, fn r, acc ->
      Map.put(acc, {row + r, col}, false)
    end)
  end

  def place_timing_patterns(matrix, size) do
    Enum.reduce(8..(size - 9), matrix, fn i, acc ->
      acc
      |> Map.put({6, i}, rem(i, 2) == 0)
      |> Map.put({i, 6}, rem(i, 2) == 0)
    end)
  end

  def place_alignment_patterns(matrix, version, _size) when version < 2, do: matrix

  def place_alignment_patterns(matrix, version, size) do
    centers = QQR.Version.alignment_pattern_centers(version)

    for row <- centers,
        col <- centers,
        not skip_alignment?(row, col, size),
        reduce: matrix do
      acc -> place_alignment_pattern(acc, row, col)
    end
  end

  defp skip_alignment?(row, col, size) do
    (row == 6 and col == 6) or
      (row == 6 and col == size - 7) or
      (row == size - 7 and col == 6)
  end

  defp place_alignment_pattern(matrix, center_row, center_col) do
    for dr <- -2..2, dc <- -2..2, reduce: matrix do
      acc ->
        val = abs(dr) == 2 or abs(dc) == 2 or (dr == 0 and dc == 0)
        Map.put(acc, {center_row + dr, center_col + dc}, val)
    end
  end

  defp place_dark_module(matrix, version) do
    Map.put(matrix, {4 * version + @dark_module_row_offset, 8}, true)
  end

  defp reserve_format_areas(matrix, size) do
    matrix =
      Enum.reduce(0..8, matrix, fn i, acc ->
        acc
        |> Map.put_new({8, i}, false)
        |> Map.put_new({i, 8}, false)
      end)

    matrix =
      Enum.reduce(0..7, matrix, fn i, acc ->
        acc
        |> Map.put_new({8, size - 1 - i}, false)
        |> Map.put_new({size - 1 - i, 8}, false)
      end)

    matrix
  end

  defp reserve_version_areas(matrix, version, size) when version >= 7 do
    for i <- 0..5, j <- 0..2, reduce: matrix do
      acc ->
        acc
        |> Map.put_new({i, size - 11 + j}, false)
        |> Map.put_new({size - 11 + j, i}, false)
    end
  end

  defp reserve_version_areas(matrix, _version, _size), do: matrix

  def place_data(matrix, bits, size, version) do
    reserved = Map.keys(matrix) |> MapSet.new()

    {matrix, _} =
      zigzag_coords(size)
      |> Enum.reject(fn {row, col} ->
        MapSet.member?(reserved, {row, col}) or
          not data_module?(row, col, size, version)
      end)
      |> Enum.reduce({matrix, bits}, fn
        _coord, {mat, []} -> {mat, []}
        {row, col}, {mat, [bit | rest]} -> {Map.put(mat, {row, col}, bit == 1), rest}
      end)

    matrix
  end

  defp zigzag_coords(size) do
    col_pairs = build_column_pairs(size - 1, [])

    Enum.flat_map(col_pairs, fn {col, going_up} ->
      rows = if going_up, do: (size - 1)..0//-1, else: 0..(size - 1)

      Enum.flat_map(rows, fn row ->
        [{row, col}, {row, col - 1}]
      end)
    end)
  end

  defp build_column_pairs(col, acc) when col <= 0, do: Enum.reverse(acc)

  defp build_column_pairs(col, acc) do
    col = if col == 6, do: col - 1, else: col
    going_up = rem(length(acc), 2) == 0
    build_column_pairs(col - 2, [{col, going_up} | acc])
  end

  def data_module?(row, col, size, version) do
    not (in_finder_or_separator?(row, col, size) or
           in_timing?(row, col) or
           in_alignment?(row, col, version, size) or
           dark_module?(row, col, version) or
           in_format_area?(row, col, size) or
           in_version_area?(row, col, version, size))
  end

  defp in_finder_or_separator?(row, col, size) do
    (row <= 8 and col <= 8) or
      (row <= 8 and col >= size - 8) or
      (row >= size - 8 and col <= 8)
  end

  defp in_timing?(6, col) when col >= 8, do: true
  defp in_timing?(row, 6) when row >= 8, do: true
  defp in_timing?(_, _), do: false

  defp in_alignment?(_row, _col, version, _size) when version < 2, do: false

  defp in_alignment?(row, col, version, size) do
    centers = QQR.Version.alignment_pattern_centers(version)

    Enum.any?(centers, fn cr ->
      Enum.any?(centers, fn cc ->
        not skip_alignment?(cr, cc, size) and
          abs(row - cr) <= 2 and abs(col - cc) <= 2
      end)
    end)
  end

  defp dark_module?(row, col, version),
    do: row == 4 * version + @dark_module_row_offset and col == 8

  defp in_format_area?(row, 8, _size) when row <= 8, do: true
  defp in_format_area?(8, col, _size) when col <= 8, do: true
  defp in_format_area?(8, col, size) when col >= size - 8, do: true
  defp in_format_area?(row, 8, size) when row >= size - 8, do: true
  defp in_format_area?(_, _, _), do: false

  defp in_version_area?(row, col, version, size) when version >= 7 do
    (row <= 5 and col >= size - 11 and col <= size - 9) or
      (col <= 5 and row >= size - 11 and row <= size - 9)
  end

  defp in_version_area?(_, _, _, _), do: false
end
