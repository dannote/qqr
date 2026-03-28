defmodule QQR.Locator do
  @moduledoc false

  alias QQR.BitMatrix

  @max_finder_patterns_to_search 4
  @min_quad_ratio 0.5
  @max_quad_ratio 1.5
  @finder_ratios [1, 1, 3, 1, 1]
  @alignment_ratios [1, 1, 1]

  @type point :: {number(), number()}
  @type location :: %{
          top_left: point(),
          top_right: point(),
          bottom_left: point(),
          alignment: point() | nil,
          dimension: pos_integer()
        }

  @spec locate(BitMatrix.t()) :: [location()] | nil
  def locate(%BitMatrix{} = matrix) do
    {finder_quads, alignment_quads} = scan_quads(matrix)

    scored =
      finder_quads
      |> Enum.filter(fn q -> q.bottom.y - q.top.y >= 2 end)
      |> Enum.map(fn q -> score_quad(q, matrix) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.score)

    groups = group_finder_patterns(scored)

    if groups == [] do
      nil
    else
      best = hd(groups)
      [p1, p2, p3] = best.points

      {top_left, top_right, bottom_left} =
        reorder_finder_patterns({p1.x, p1.y}, {p2.x, p2.y}, {p3.x, p3.y})

      result = try_alignment(matrix, alignment_quads, top_left, top_right, bottom_left)

      mid_top_left = recenter_location(matrix, top_left)
      mid_top_right = recenter_location(matrix, top_right)
      mid_bottom_left = recenter_location(matrix, bottom_left)

      centered_result =
        try_alignment(matrix, alignment_quads, mid_top_left, mid_top_right, mid_bottom_left)

      case result ++ centered_result do
        [] -> nil
        locations -> locations
      end
    end
  end

  @doc false
  @spec reorder_finder_patterns(point(), point(), point()) ::
          {point(), point(), point()}
  def reorder_finder_patterns(p1, p2, p3) do
    d12 = distance(p1, p2)
    d23 = distance(p2, p3)
    d13 = distance(p1, p3)

    {bottom_left, top_left, top_right} =
      cond do
        d23 >= d12 and d23 >= d13 -> {p2, p1, p3}
        d13 >= d23 and d13 >= d12 -> {p1, p2, p3}
        true -> {p1, p3, p2}
      end

    {tl_x, tl_y} = top_left
    {tr_x, tr_y} = top_right
    {bl_x, bl_y} = bottom_left

    cross = (tr_x - tl_x) * (bl_y - tl_y) - (tr_y - tl_y) * (bl_x - tl_x)

    if cross < 0 do
      {top_left, bottom_left, top_right}
    else
      {top_left, top_right, bottom_left}
    end
  end

  # -- Scanning --

  defp scan_quads(%BitMatrix{height: height} = matrix) do
    initial = %{
      finder_quads: [],
      active_finder: [],
      alignment_quads: [],
      active_alignment: []
    }

    step = if height > 100, do: 2, else: 1

    result =
      Enum.reduce(0..height//step, initial, fn y, acc ->
        {finder_matches, alignment_matches} = scan_row(matrix, y)

        {active_finder, finished_finder} =
          update_active_quads(acc.active_finder, finder_matches, y, _min_height = 2)

        {active_alignment, finished_alignment} =
          update_active_quads(acc.active_alignment, alignment_matches, y, _min_height = 0)

        %{
          acc
          | finder_quads: acc.finder_quads ++ finished_finder,
            active_finder: active_finder,
            alignment_quads: acc.alignment_quads ++ finished_alignment,
            active_alignment: active_alignment
        }
      end)

    final_finder =
      result.active_finder
      |> Enum.filter(fn q -> q.bottom.y - q.top.y >= 2 end)

    {result.finder_quads ++ final_finder, result.alignment_quads ++ result.active_alignment}
  end

  defp scan_row(%BitMatrix{width: width} = matrix, y) do
    initial = %{
      scans: {0, 0, 0, 0, 0},
      length: 0,
      last_bit: false,
      finder_matches: [],
      alignment_matches: []
    }

    result =
      Enum.reduce(-1..width, initial, fn x, acc ->
        v = BitMatrix.get(matrix, x, y)

        if v == acc.last_bit do
          %{acc | length: acc.length + 1}
        else
          {_s0, s1, s2, s3, s4} = acc.scans
          scans = {s1, s2, s3, s4, acc.length}

          acc = %{acc | scans: scans, length: 1, last_bit: v}

          acc = check_finder_pattern(acc, scans, x, y, v)
          check_alignment_pattern(acc, scans, x, y, v)
        end
      end)

    {Enum.reverse(result.finder_matches), Enum.reverse(result.alignment_matches)}
  end

  defp check_finder_pattern(acc, scans, x, y, v) do
    {s0, s1, s2, s3, s4} = scans

    total = s0 + s1 + s2 + s3 + s4
    avg = total / 7

    valid =
      not v and
        avg > 0 and
        abs(s0 - avg) < avg and
        abs(s1 - avg) < avg and
        abs(s2 - 3 * avg) < 3 * avg and
        abs(s3 - avg) < avg and
        abs(s4 - avg) < avg

    if valid do
      end_x = x - s3 - s4
      start_x = end_x - s2
      line = %{start_x: start_x, end_x: end_x, y: y}
      %{acc | finder_matches: [line | acc.finder_matches]}
    else
      acc
    end
  end

  defp check_alignment_pattern(acc, scans, x, y, v) do
    {_s0, _s1, s2, s3, s4} = scans

    total = s2 + s3 + s4
    avg = total / 3

    valid =
      v and
        avg > 0 and
        abs(s2 - avg) < avg and
        abs(s3 - avg) < avg and
        abs(s4 - avg) < avg

    if valid do
      end_x = x - s4
      start_x = end_x - s3
      line = %{start_x: start_x, end_x: end_x, y: y}
      %{acc | alignment_matches: [line | acc.alignment_matches]}
    else
      acc
    end
  end

  defp update_active_quads(active, matches, y, min_height) do
    still_active =
      Enum.reduce(matches, active, fn line, quads ->
        case find_matching_quad(quads, line) do
          {matched, rest} ->
            updated = %{matched | bottom: line}
            [updated | rest]

          nil ->
            new_quad = %{top: line, bottom: line}
            [new_quad | quads]
        end
      end)

    {kept, finished} =
      Enum.split_with(still_active, fn q -> q.bottom.y == y end)

    finished =
      if min_height > 0 do
        Enum.filter(finished, fn q -> q.bottom.y - q.top.y >= min_height end)
      else
        finished
      end

    {kept, finished}
  end

  defp find_matching_quad(quads, line) do
    Enum.reduce_while(quads, nil, fn q, _acc ->
      overlaps =
        (line.start_x >= q.bottom.start_x and line.start_x <= q.bottom.end_x) or
          (line.end_x >= q.bottom.start_x and line.start_x <= q.bottom.end_x) or
          (line.start_x <= q.bottom.start_x and line.end_x >= q.bottom.end_x and
             quad_ratio_valid?(line, q))

      if overlaps do
        rest = Enum.reject(quads, &(&1 == q))
        {:halt, {q, rest}}
      else
        {:cont, nil}
      end
    end)
  end

  defp quad_ratio_valid?(line, q) do
    bottom_width = q.bottom.end_x - q.bottom.start_x
    line_width = line.end_x - line.start_x

    if bottom_width == 0 do
      false
    else
      ratio = line_width / bottom_width
      ratio > @min_quad_ratio and ratio < @max_quad_ratio
    end
  end

  # -- Scoring --

  defp score_quad(q, matrix) do
    x = (q.top.start_x + q.top.end_x + q.bottom.start_x + q.bottom.end_x) / 4
    y = (q.top.y + q.bottom.y + 1) / 2

    rx = round(x)
    ry = round(y)

    if BitMatrix.get(matrix, rx, ry) do
      top_width = q.top.end_x - q.top.start_x
      bottom_width = q.bottom.end_x - q.bottom.start_x
      height = q.bottom.y - q.top.y + 1
      size = (top_width + bottom_width + height) / 3
      score = score_pattern({rx, ry}, @finder_ratios, matrix)
      %{score: score, x: x, y: y, size: size}
    else
      nil
    end
  end

  defp group_finder_patterns(scored) do
    scored
    |> Enum.with_index()
    |> Enum.flat_map(fn {point, i} ->
      if i > @max_finder_patterns_to_search,
        do: [],
        else: build_group_for_point(point, scored)
    end)
    |> Enum.sort_by(& &1.score)
  end

  defp build_group_for_point(point, scored) do
    others =
      scored
      |> Enum.reject(&(&1 == point))
      |> Enum.map(fn p ->
        size_penalty = (p.size - point.size) ** 2 / max(point.size, 0.001)
        %{x: p.x, y: p.y, score: p.score + size_penalty, size: p.size}
      end)
      |> Enum.sort_by(& &1.score)

    if length(others) < 2 do
      []
    else
      total_score = point.score + Enum.at(others, 0).score + Enum.at(others, 1).score
      [%{points: [point | Enum.take(others, 2)], score: total_score}]
    end
  end

  # -- Black/white run counting (Bresenham) --

  defp count_black_white_run(origin, endpoint, matrix, length) do
    towards = count_black_white_run_towards(origin, endpoint, matrix, ceil(length / 2))

    {ox, oy} = origin
    {ex, ey} = endpoint
    away_end = {ox - (ex - ox), oy - (ey - oy)}
    away = count_black_white_run_towards(origin, away_end, matrix, ceil(length / 2))

    [towards_first | towards_rest] = towards
    [away_first | away_rest] = away

    middle = towards_first + away_first - 1

    Enum.reverse(away_rest) ++ [middle | towards_rest]
  end

  defmodule BresenhamState do
    @moduledoc false
    defstruct [
      :to_x,
      :dx,
      :dy,
      :x_step,
      :y_step,
      :to_y,
      :steep,
      :max_switches,
      :matrix
    ]
  end

  defp count_black_white_run_towards(origin, endpoint, matrix, length) do
    {ox, oy} = origin
    {ex, ey} = endpoint

    from_x_init = floor(ox)
    from_y_init = floor(oy)
    to_x_init = floor(ex)
    to_y_init = floor(ey)

    steep = abs(to_y_init - from_y_init) > abs(to_x_init - from_x_init)

    {from_x, from_y, to_x, to_y} =
      if steep do
        {from_y_init, from_x_init, to_y_init, to_x_init}
      else
        {from_x_init, from_y_init, to_x_init, to_y_init}
      end

    dx = abs(to_x - from_x)
    dy = abs(to_y - from_y)

    state = %BresenhamState{
      to_x: to_x,
      dx: dx,
      dy: dy,
      x_step: if(from_x < to_x, do: 1, else: -1),
      y_step: if(from_y < to_y, do: 1, else: -1),
      to_y: to_y,
      steep: steep,
      max_switches: length,
      matrix: matrix
    }

    switch_points = [{floor(ox), floor(oy)}]
    bresenham_walk(from_x, from_y, div(-dx, 2), true, switch_points, state)
  end

  defp bresenham_walk(x, y, error, current_pixel, switch_points, %BresenhamState{} = s) do
    if x == s.to_x + s.x_step do
      build_distances(switch_points, s.max_switches)
    else
      {real_x, real_y} = if s.steep, do: {y, x}, else: {x, y}
      pixel = BitMatrix.get(s.matrix, real_x, real_y)

      {switch_points, current_pixel} =
        update_switch_points(pixel, current_pixel, switch_points, real_x, real_y, s.max_switches)

      {new_y, new_error} = advance_y(y, error + s.dy, switch_points, s)

      bresenham_walk(x + s.x_step, new_y, new_error, current_pixel, switch_points, s)
    end
  catch
    {:done, result} -> result
  end

  defp advance_y(y, new_error, switch_points, %BresenhamState{} = s) when new_error > 0 do
    if y == s.to_y,
      do: throw({:done, build_distances(switch_points, s.max_switches)})

    {y + s.y_step, new_error - s.dx}
  end

  defp advance_y(y, new_error, _switch_points, _state), do: {y, new_error}

  defp update_switch_points(pixel, current_pixel, switch_points, _rx, _ry, _max)
       when pixel == current_pixel,
       do: {switch_points, current_pixel}

  defp update_switch_points(_pixel, current_pixel, switch_points, real_x, real_y, max_switches) do
    new_points = [{real_x, real_y} | switch_points]

    if Kernel.length(new_points) == max_switches + 1,
      do: throw({:done, build_distances(new_points, max_switches)})

    {new_points, not current_pixel}
  end

  defp build_distances(switch_points_reversed, length) do
    switch_points = Enum.reverse(switch_points_reversed)

    Enum.map(0..(length - 1), fn i ->
      case {Enum.at(switch_points, i), Enum.at(switch_points, i + 1)} do
        {nil, _} -> 0
        {_, nil} -> 0
        {a, b} -> distance(a, b)
      end
    end)
  end

  # -- Pattern scoring --

  defp score_pattern(point, ratios, matrix) do
    {px, py} = point
    ratios_length = Kernel.length(ratios)

    horizontal = count_black_white_run(point, {-1, py}, matrix, ratios_length)
    vertical = count_black_white_run(point, {px, -1}, matrix, ratios_length)

    tl_x = max(0, px - py) - 1
    tl_y = max(0, py - px) - 1
    diag_down = count_black_white_run(point, {tl_x, tl_y}, matrix, ratios_length)

    br_x = min(matrix.width, px + py) + 1
    br_y = min(matrix.height, py + px) + 1
    diag_up = count_black_white_run(point, {br_x, br_y}, matrix, ratios_length)

    h = score_black_white_run(horizontal, ratios)
    v = score_black_white_run(vertical, ratios)
    dd = score_black_white_run(diag_down, ratios)
    du = score_black_white_run(diag_up, ratios)

    ratio_error =
      :math.sqrt(
        h.error * h.error + v.error * v.error + dd.error * dd.error + du.error * du.error
      )

    avg_size = (h.average_size + v.average_size + dd.average_size + du.average_size) / 4

    size_error =
      ((h.average_size - avg_size) ** 2 + (v.average_size - avg_size) ** 2 +
         (dd.average_size - avg_size) ** 2 + (du.average_size - avg_size) ** 2) /
        max(avg_size, 0.001)

    ratio_error + size_error
  end

  defp score_black_white_run(sequence, ratios) do
    total_seq = Enum.sum(sequence)
    total_ratios = Enum.sum(ratios)
    average_size = total_seq / max(total_ratios, 0.001)

    error =
      Enum.zip(sequence, ratios)
      |> Enum.reduce(0, fn {s, r}, acc ->
        acc + (s - r * average_size) ** 2
      end)

    %{average_size: average_size, error: error}
  end

  defp try_alignment(matrix, alignment_quads, top_left, top_right, bottom_left) do
    case find_alignment_pattern(matrix, alignment_quads, top_right, top_left, bottom_left) do
      {:ok, alignment, dimension} ->
        [
          %{
            top_left: top_left,
            top_right: top_right,
            bottom_left: bottom_left,
            alignment: alignment,
            dimension: dimension
          }
        ]

      :error ->
        []
    end
  end

  # -- Recenter --

  defp recenter_location(matrix, {px, py}) do
    rx = round(px)
    ry = round(py)

    left_x = find_edge(matrix, rx, ry, -1, :horizontal)
    right_x = find_edge(matrix, rx, ry, 1, :horizontal)
    new_x = (left_x + right_x) / 2

    top_y = find_edge(matrix, round(new_x), ry, -1, :vertical)
    bottom_y = find_edge(matrix, round(new_x), ry, 1, :vertical)
    new_y = (top_y + bottom_y) / 2

    {new_x, new_y}
  end

  defp find_edge(matrix, x, y, step, :horizontal) do
    if BitMatrix.get(matrix, x, y), do: find_edge(matrix, x + step, y, step, :horizontal), else: x
  end

  defp find_edge(matrix, x, y, step, :vertical) do
    if BitMatrix.get(matrix, x, y), do: find_edge(matrix, x, y + step, step, :vertical), else: y
  end

  # -- Alignment pattern --

  defp find_alignment_pattern(matrix, alignment_quads, top_right, top_left, bottom_left) do
    case compute_dimension(top_left, top_right, bottom_left, matrix) do
      {:ok, dimension, module_size} ->
        alignment =
          locate_alignment(matrix, alignment_quads, top_right, top_left, bottom_left, module_size)

        {:ok, alignment, dimension}

      :error ->
        :error
    end
  end

  defp locate_alignment(matrix, alignment_quads, top_right, top_left, bottom_left, module_size) do
    {tr_x, tr_y} = top_right
    {tl_x, tl_y} = top_left
    {bl_x, bl_y} = bottom_left

    {br_x, br_y} = {tr_x - tl_x + bl_x, tr_y - tl_y + bl_y}

    modules_between =
      (distance(top_left, bottom_left) + distance(top_left, top_right)) / 2 / module_size

    correction = 1 - 3 / modules_between
    expected = {tl_x + correction * (br_x - tl_x), tl_y + correction * (br_y - tl_y)}

    candidates = score_alignment_candidates(matrix, alignment_quads, expected)

    if modules_between >= 15 and candidates != [] do
      best = hd(candidates)
      {best.x, best.y}
    else
      expected
    end
  end

  defp score_alignment_candidates(matrix, alignment_quads, expected) do
    alignment_quads
    |> Enum.map(&score_alignment_quad(&1, matrix, expected))
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.score)
  end

  defp score_alignment_quad(q, matrix, expected) do
    x = (q.top.start_x + q.top.end_x + q.bottom.start_x + q.bottom.end_x) / 4
    y = (q.top.y + q.bottom.y + 1) / 2

    if BitMatrix.get(matrix, floor(x), floor(y)) do
      size_score = score_pattern({floor(x), floor(y)}, @alignment_ratios, matrix)
      dist = distance({x, y}, expected)
      %{x: x, y: y, score: size_score + dist}
    end
  end

  defp compute_dimension(top_left, top_right, bottom_left, matrix) do
    runs = [
      count_black_white_run(top_left, bottom_left, matrix, 5),
      count_black_white_run(top_left, top_right, matrix, 5),
      count_black_white_run(bottom_left, top_left, matrix, 5),
      count_black_white_run(top_right, top_left, matrix, 5)
    ]

    module_size = Enum.reduce(runs, 0, fn r, acc -> acc + Enum.sum(r) / 7 end) / 4

    if module_size < 1 do
      :error
    else
      top_dim = round(distance(top_left, top_right) / module_size)
      side_dim = round(distance(top_left, bottom_left) / module_size)
      dimension = floor((top_dim + side_dim) / 2) + 7

      dimension =
        case rem(dimension, 4) do
          0 -> dimension + 1
          2 -> dimension - 1
          _ -> dimension
        end

      {:ok, dimension, module_size}
    end
  end

  # -- Helpers --

  defp distance({x1, y1}, {x2, y2}) do
    :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2)
  end
end
