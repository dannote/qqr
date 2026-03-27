defmodule QQR.Binarizer do
  @moduledoc false

  alias QQR.BitMatrix

  @region_size 8
  @min_dynamic_range 24

  @spec binarize(binary(), pos_integer(), pos_integer(), keyword()) ::
          {BitMatrix.t(), BitMatrix.t() | nil}
  def binarize(rgba, width, height, opts \\ []) do
    invert = Keyword.get(opts, :invert, false)

    gray = to_grayscale(rgba, width, height)
    num_bx = ceil_div(width, @region_size)
    num_by = ceil_div(height, @region_size)
    black_points = compute_black_points(gray, width, height, num_bx, num_by)
    apply_thresholds(gray, width, height, black_points, num_bx, num_by, invert)
  end

  defp ceil_div(a, b), do: div(a + b - 1, b)

  # --- Grayscale conversion ---

  defp to_grayscale(rgba, width, height) do
    size = width * height

    gray =
      Enum.reduce(0..(size - 1)//1, <<>>, fn i, acc ->
        offset = i * 4
        <<_::binary-size(offset), r, g, b, _a, _::binary>> = rgba
        lum = trunc(0.2126 * r + 0.7152 * g + 0.0722 * b)
        <<acc::binary, lum>>
      end)

    ^size = byte_size(gray)
    gray
  end

  defp gray_get(gray, x, y, width, height) do
    if x >= 0 and x < width and y >= 0 and y < height do
      :binary.at(gray, y * width + x)
    else
      0
    end
  end

  # --- Block black-point estimation ---

  defp compute_black_points(gray, width, height, num_bx, num_by) do
    Enum.reduce(0..(num_by - 1)//1, :array.new(num_bx * num_by, default: 0), fn vy, bp ->
      Enum.reduce(0..(num_bx - 1)//1, bp, fn hx, bp_acc ->
        {sum, min_val, max_val} = block_stats(gray, width, height, hx, vy)
        average = div(sum, @region_size * @region_size)

        average =
          if max_val - min_val <= @min_dynamic_range do
            avg = div(min_val, 2)

            if vy > 0 and hx > 0 do
              top = :array.get((vy - 1) * num_bx + hx, bp_acc)
              left = :array.get(vy * num_bx + (hx - 1), bp_acc)
              diag = :array.get((vy - 1) * num_bx + (hx - 1), bp_acc)
              neighbor_avg = div(top + 2 * left + diag, 4)
              if min_val < neighbor_avg, do: neighbor_avg, else: avg
            else
              avg
            end
          else
            average
          end

        :array.set(vy * num_bx + hx, average, bp_acc)
      end)
    end)
  end

  defp block_stats(gray, width, height, hx, vy) do
    Enum.reduce(0..(@region_size - 1)//1, {0, 255, 0}, fn dy, {sum, mn, mx} ->
      Enum.reduce(0..(@region_size - 1)//1, {sum, mn, mx}, fn dx, {s, n, x} ->
        lum = gray_get(gray, hx * @region_size + dx, vy * @region_size + dy, width, height)
        {s + lum, min(n, lum), max(x, lum)}
      end)
    end)
  end

  # --- Threshold application with 5×5 smoothing ---

  defp apply_thresholds(gray, width, height, black_points, num_bx, num_by, invert) do
    initial_normal = BitMatrix.new(width, height)
    initial_inverted = if invert, do: BitMatrix.new(width, height)

    {normal, inverted} =
      Enum.reduce(0..(num_by - 1)//1, {initial_normal, initial_inverted}, fn vy, acc ->
        Enum.reduce(0..(num_bx - 1)//1, acc, fn hx, {norm, inv} ->
          threshold = smoothed_threshold(black_points, num_bx, num_by, hx, vy)

          Enum.reduce(0..(@region_size - 1)//1, {norm, inv}, fn dy, acc2 ->
            Enum.reduce(0..(@region_size - 1)//1, acc2, fn dx, {n, i} ->
              x = hx * @region_size + dx
              y = vy * @region_size + dy

              if x < width and y < height do
                lum = :binary.at(gray, y * width + x)
                is_black = lum <= threshold

                n = BitMatrix.set(n, x, y, is_black)
                i = if i, do: BitMatrix.set(i, x, y, not is_black), else: nil
                {n, i}
              else
                {n, i}
              end
            end)
          end)
        end)
      end)

    {normal, inverted}
  end

  defp smoothed_threshold(black_points, num_bx, num_by, hx, vy) do
    left = hx |> max(2) |> min(num_bx - 3)
    top = vy |> max(2) |> min(num_by - 3)

    sum =
      Enum.reduce(-2..2//1, 0, fn dy, acc ->
        row = top + dy
        Enum.reduce(-2..2//1, acc, fn dx, s ->
          col = left + dx

          if row >= 0 and row < num_by and col >= 0 and col < num_bx do
            s + :array.get(row * num_bx + col, black_points)
          else
            s
          end
        end)
      end)

    count =
      Enum.reduce(-2..2//1, 0, fn dy, acc ->
        row = top + dy
        Enum.reduce(-2..2//1, acc, fn dx, c ->
          col = left + dx

          if row >= 0 and row < num_by and col >= 0 and col < num_bx do
            c + 1
          else
            c
          end
        end)
      end)

    if count > 0, do: div(sum, count), else: 0
  end
end
