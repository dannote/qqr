defmodule QQR.Binarizer do
  @moduledoc false

  alias QQR.BitMatrix

  @region_size 8
  @min_dynamic_range 24
  @max_luminance 255

  @spec binarize(binary(), pos_integer(), pos_integer(), keyword()) ::
          {BitMatrix.t(), BitMatrix.t() | nil}
  def binarize(rgba, width, height, opts \\ []) do
    invert = Keyword.get(opts, :invert, false)

    gray = to_grayscale(rgba)
    num_bx = ceil_div(width, @region_size)
    num_by = ceil_div(height, @region_size)
    black_points = compute_black_points(gray, width, height, num_bx, num_by)
    thresholds = build_threshold_tuple(black_points, num_bx, num_by)
    build_matrices(gray, width, height, thresholds, num_bx, num_by, invert)
  end

  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp to_grayscale(rgba) do
    do_grayscale(rgba, [])
  end

  defp do_grayscale(<<r, g, b, _a, rest::binary>>, acc) do
    lum = div(2126 * r + 7152 * g + 722 * b, 10_000)
    do_grayscale(rest, [lum | acc])
  end

  defp do_grayscale(<<>>, acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()

  defp compute_black_points(gray, width, height, num_bx, num_by) do
    Enum.reduce(0..(num_by - 1)//1, :array.new(num_bx * num_by, default: 0), fn vy, bp ->
      Enum.reduce(0..(num_bx - 1)//1, bp, fn hx, bp_acc ->
        average = compute_block_average(gray, width, height, hx, vy, num_bx, bp_acc)
        :array.set(vy * num_bx + hx, average, bp_acc)
      end)
    end)
  end

  defp compute_block_average(gray, width, height, hx, vy, num_bx, bp_acc) do
    {sum, min_val, max_val} = block_stats(gray, width, height, hx, vy)
    average = div(sum, @region_size * @region_size)

    if max_val - min_val > @min_dynamic_range do
      average
    else
      fallback = div(min_val, 2)
      neighbor_adjusted_average(bp_acc, num_bx, hx, vy, min_val, fallback)
    end
  end

  defp neighbor_adjusted_average(bp_acc, num_bx, hx, vy, min_val, fallback) do
    if vy > 0 and hx > 0 do
      top = :array.get((vy - 1) * num_bx + hx, bp_acc)
      left = :array.get(vy * num_bx + (hx - 1), bp_acc)
      diag = :array.get((vy - 1) * num_bx + (hx - 1), bp_acc)
      neighbor_avg = div(top + 2 * left + diag, 4)
      if min_val < neighbor_avg, do: neighbor_avg, else: fallback
    else
      fallback
    end
  end

  defp block_stats(gray, width, height, hx, vy) do
    for dy <- 0..(@region_size - 1)//1,
        dx <- 0..(@region_size - 1)//1,
        reduce: {0, @max_luminance, 0} do
      {s, mn, mx} ->
        lum = block_pixel(gray, width, height, hx * @region_size + dx, vy * @region_size + dy)
        {s + lum, min(mn, lum), max(mx, lum)}
    end
  end

  defp block_pixel(gray, width, height, px, py) do
    if px < width and py < height,
      do: :binary.at(gray, py * width + px),
      else: 0
  end

  defp build_threshold_tuple(black_points, num_bx, num_by) do
    list =
      for vy <- 0..(num_by - 1)//1,
          hx <- 0..(num_bx - 1)//1 do
        smoothed_threshold(black_points, num_bx, num_by, hx, vy)
      end

    List.to_tuple(list)
  end

  defp build_matrices(gray, width, height, thresholds, num_bx, num_by, invert) do
    max_hx = num_bx - 1
    max_vy = num_by - 1
    normal_list = classify_pixels(gray, 0, width, thresholds, max_hx, max_vy, num_bx, [])
    normal = %BitMatrix{width: width, height: height, data: List.to_tuple(normal_list)}

    inverted =
      if invert do
        inv_list = Enum.map(normal_list, fn b -> 1 - b end)
        %BitMatrix{width: width, height: height, data: List.to_tuple(inv_list)}
      end

    {normal, inverted}
  end

  defp classify_pixels(<<lum, rest::binary>>, idx, width, thresholds, max_hx, max_vy, num_bx, acc) do
    hx = min(div(rem(idx, width), @region_size), max_hx)
    vy = min(div(div(idx, width), @region_size), max_vy)
    threshold = :erlang.element(vy * num_bx + hx + 1, thresholds)
    bit = if lum <= threshold, do: 1, else: 0

    classify_pixels(rest, idx + 1, width, thresholds, max_hx, max_vy, num_bx, [bit | acc])
  end

  defp classify_pixels(<<>>, _idx, _width, _thresholds, _max_hx, _max_vy, _num_bx, acc) do
    Enum.reverse(acc)
  end

  defp smoothed_threshold(black_points, num_bx, num_by, hx, vy) do
    left = hx |> max(2) |> min(num_bx - 3)
    top = vy |> max(2) |> min(num_by - 3)

    {sum, count} =
      for dy <- -2..2//1,
          dx <- -2..2//1,
          row = top + dy,
          col = left + dx,
          row >= 0 and row < num_by and col >= 0 and col < num_bx,
          reduce: {0, 0} do
        {s, c} -> {s + :array.get(row * num_bx + col, black_points), c + 1}
      end

    if count > 0, do: div(sum, count), else: 0
  end
end
