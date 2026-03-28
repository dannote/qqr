defmodule QQR.Encoder.Mask do
  @moduledoc false

  alias QQR.Encoder.Format
  alias QQR.Encoder.Matrix

  def apply_mask(matrix, mask, size, version) do
    for row <- 0..(size - 1),
        col <- 0..(size - 1),
        Matrix.data_module?(row, col, size, version),
        mask_applies?(mask, row, col),
        reduce: matrix do
      acc ->
        current = Map.get(acc, {row, col}, false)
        Map.put(acc, {row, col}, not current)
    end
  end

  def select_best_mask(matrix, size, version, ec_level, requested_mask)
      when is_integer(requested_mask) do
    matrix
    |> apply_mask(requested_mask, size, version)
    |> Format.write_format_info(ec_level, requested_mask, size)
    |> Format.write_version_info(version, size)
    |> then(&{requested_mask, &1})
  end

  def select_best_mask(matrix, size, version, ec_level, nil) do
    0..7
    |> Enum.map(fn mask ->
      masked = apply_mask(matrix, mask, size, version)
      with_format = Format.write_format_info(masked, ec_level, mask, size)
      with_version = Format.write_version_info(with_format, version, size)
      penalty = evaluate_penalty(with_version, size)
      {mask, with_version, penalty}
    end)
    |> Enum.min_by(fn {_, _, penalty} -> penalty end)
    |> then(fn {mask, final_matrix, _} -> {mask, final_matrix} end)
  end

  def evaluate_penalty(matrix, size) do
    penalty_rule_1(matrix, size) +
      penalty_rule_2(matrix, size) +
      penalty_rule_3(matrix, size) +
      penalty_rule_4(matrix, size)
  end

  defp penalty_rule_1(matrix, size) do
    rows_penalty =
      Enum.reduce(0..(size - 1), 0, fn row, total ->
        0..(size - 1)
        |> Enum.map(fn col -> Map.get(matrix, {row, col}, false) end)
        |> run_penalty()
        |> Kernel.+(total)
      end)

    cols_penalty =
      Enum.reduce(0..(size - 1), 0, fn col, total ->
        0..(size - 1)
        |> Enum.map(fn row -> Map.get(matrix, {row, col}, false) end)
        |> run_penalty()
        |> Kernel.+(total)
      end)

    rows_penalty + cols_penalty
  end

  defp run_penalty(modules) do
    {penalty, _last, _count} =
      Enum.reduce(modules, {0, nil, 0}, fn mod, {pen, last, cnt} ->
        if mod == last do
          run_penalty_consecutive(pen, mod, cnt + 1)
        else
          {pen, mod, 1}
        end
      end)

    penalty
  end

  defp run_penalty_consecutive(pen, mod, 5), do: {pen + 3, mod, 5}
  defp run_penalty_consecutive(pen, mod, cnt) when cnt > 5, do: {pen + 1, mod, cnt}
  defp run_penalty_consecutive(pen, mod, cnt), do: {pen, mod, cnt}

  defp penalty_rule_2(matrix, size) do
    for row <- 0..(size - 2), col <- 0..(size - 2), reduce: 0 do
      acc ->
        val = Map.get(matrix, {row, col}, false)

        if val == Map.get(matrix, {row, col + 1}, false) and
             val == Map.get(matrix, {row + 1, col}, false) and
             val == Map.get(matrix, {row + 1, col + 1}, false) do
          acc + 3
        else
          acc
        end
    end
  end

  defp penalty_rule_3(matrix, size) do
    pattern_a = [true, false, true, true, true, false, true, false, false, false, false]
    pattern_b = Enum.reverse(pattern_a)

    rows_penalty =
      Enum.reduce(0..(size - 1), 0, fn row, total ->
        modules = for col <- 0..(size - 1), do: Map.get(matrix, {row, col}, false)
        total + count_pattern_matches(modules, pattern_a, pattern_b)
      end)

    cols_penalty =
      Enum.reduce(0..(size - 1), 0, fn col, total ->
        modules = for row <- 0..(size - 1), do: Map.get(matrix, {row, col}, false)
        total + count_pattern_matches(modules, pattern_a, pattern_b)
      end)

    (rows_penalty + cols_penalty) * 40
  end

  defp mask_applies?(0, row, col), do: rem(row + col, 2) == 0
  defp mask_applies?(1, row, _col), do: rem(row, 2) == 0
  defp mask_applies?(2, _row, col), do: rem(col, 3) == 0
  defp mask_applies?(3, row, col), do: rem(row + col, 3) == 0
  defp mask_applies?(4, row, col), do: rem(div(row, 2) + div(col, 3), 2) == 0
  defp mask_applies?(5, row, col), do: rem(row * col, 2) + rem(row * col, 3) == 0
  defp mask_applies?(6, row, col), do: rem(rem(row * col, 2) + rem(row * col, 3), 2) == 0
  defp mask_applies?(7, row, col), do: rem(rem(row + col, 2) + rem(row * col, 3), 2) == 0

  defp count_pattern_matches(modules, pattern_a, pattern_b) do
    len = length(pattern_a)

    if length(modules) < len do
      0
    else
      modules
      |> Enum.chunk_every(len, 1, :discard)
      |> Enum.count(fn chunk -> chunk == pattern_a or chunk == pattern_b end)
    end
  end

  defp penalty_rule_4(matrix, size) do
    total = size * size
    dark_count = count_dark_modules(matrix, size)
    percentage = dark_count * 100 / total
    prev_multiple = floor(percentage / 5) * 5
    next_multiple = prev_multiple + 5

    (abs(prev_multiple - 50) / 5 * 10)
    |> trunc()
    |> min(trunc(abs(next_multiple - 50) / 5 * 10))
  end

  defp count_dark_modules(matrix, size) do
    for row <- 0..(size - 1), col <- 0..(size - 1), reduce: 0 do
      acc -> if Map.get(matrix, {row, col}, false), do: acc + 1, else: acc
    end
  end
end
