defmodule QQR.SVG do
  @moduledoc """
  SVG renderer for QR code matrices.

  ## Dot shapes

      :square          ■  (default)
      :rounded         ▢  rounded corners (25% radius)
      :dots            ●  circles
      :diamond         ◆  diamond / rotated square

  ## Finder pattern shapes

  Finder patterns (the three big squares in corners) can be styled
  independently with `:finder_shape`:

      :square          default
      :rounded         rounded outer ring + rounded inner
      :dots            circular outer ring + circular inner

  ## Logo embedding

  Pass a `:logo` option to embed an image or SVG in the center.
  Modules behind the logo are automatically cleared.

      QQR.SVG.render(matrix,
        logo: %{svg: ~s(<circle r="0.4" cx="0.5" cy="0.5" fill="red"/>), size: 0.25}
      )

  """

  alias QQR.BitMatrix

  @type dot_shape :: :square | :rounded | :dots | :diamond
  @type finder_shape :: :square | :rounded | :dots

  @type logo_opts :: %{
          optional(:svg) => String.t(),
          optional(:image_url) => String.t(),
          optional(:size) => float(),
          optional(:margin) => number(),
          optional(:background) => String.t()
        }

  @type option ::
          {:module_size, number()}
          | {:quiet_zone, non_neg_integer()}
          | {:color, String.t()}
          | {:background, String.t()}
          | {:dot_shape, dot_shape()}
          | {:dot_size, float()}
          | {:finder_shape, finder_shape()}
          | {:logo, logo_opts()}

  @doc """
  Render a `QQR.BitMatrix` as an SVG string.

  ## Options

    * `:module_size` — pixel size per module (default: `10`)
    * `:quiet_zone` — quiet zone in modules (default: `4`)
    * `:color` — dark module color (default: `"#000"`)
    * `:background` — background color (default: `"#fff"`)
    * `:dot_shape` — `:square`, `:rounded`, `:dots`, or `:diamond` (default: `:square`)
    * `:dot_size` — module size multiplier, 0.1–1.0 (default: `1.0`)
    * `:finder_shape` — `:square`, `:rounded`, or `:dots` (default: matches `:dot_shape` or `:square`)
    * `:logo` — logo options map (see module doc)

  """
  @spec render(BitMatrix.t(), [option()]) :: String.t()
  def render(%BitMatrix{width: w, height: h} = matrix, opts \\ []) do
    mod = Keyword.get(opts, :module_size, 10)
    quiet = Keyword.get(opts, :quiet_zone, 4)
    color = Keyword.get(opts, :color, "#000")
    bg = Keyword.get(opts, :background, "#fff")
    dot_shape = Keyword.get(opts, :dot_shape, :square)
    dot_size = Keyword.get(opts, :dot_size, 1.0)
    finder_shape = Keyword.get(opts, :finder_shape, default_finder_shape(dot_shape))
    logo_opts = Keyword.get(opts, :logo)

    total = (w + quiet * 2) * mod

    {hidden, logo_svg} = logo_placement(logo_opts, w, mod, quiet)

    finder_modules = finder_module_set(w)

    finder_svg =
      if finder_shape != :square do
        render_finders(w, quiet, mod, finder_shape, color)
      else
        ""
      end

    skip_finders? = finder_shape != :square

    paths =
      for y <- 0..(h - 1),
          x <- 0..(w - 1),
          BitMatrix.get(matrix, x, y),
          not MapSet.member?(hidden, {x, y}),
          not (skip_finders? and MapSet.member?(finder_modules, {x, y})),
          into: "" do
        px = (x + quiet) * mod
        py = (y + quiet) * mod
        module_path(px, py, mod, dot_shape, dot_size)
      end

    [
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{total} #{total}" shape-rendering="crispEdges">),
      ~s(<rect width="#{total}" height="#{total}" fill="#{bg}"/>),
      finder_svg,
      ~s(<path d="#{paths}" fill="#{color}"/>),
      logo_svg,
      "</svg>"
    ]
    |> IO.iodata_to_binary()
  end

  defp default_finder_shape(:dots), do: :dots
  defp default_finder_shape(:rounded), do: :rounded
  defp default_finder_shape(_), do: :square

  # -- Module paths --

  defp module_path(x, y, size, :square, dot_size) do
    s = size * dot_size
    o = (size - s) / 2
    "M#{x + o},#{y + o}h#{s}v#{s}h-#{s}z"
  end

  defp module_path(x, y, size, :rounded, dot_size) do
    s = size * dot_size
    o = (size - s) / 2
    r = s * 0.25
    rounded_rect_path(x + o, y + o, s, r)
  end

  defp module_path(x, y, size, :dots, dot_size) do
    r = size * dot_size / 2
    cx = x + size / 2
    cy = y + size / 2
    circle_path(cx, cy, r)
  end

  defp module_path(x, y, size, :diamond, dot_size) do
    s = size * dot_size
    cx = x + size / 2
    cy = y + size / 2
    half = s / 2
    "M#{cx},#{cy - half}l#{half},#{half}l-#{half},#{half}l-#{half},-#{half}z"
  end

  defp rounded_rect_path(x, y, s, r) do
    r = min(r, s / 2)
    d = s - 2 * r

    "M#{x + r},#{y}" <>
      "h#{d}a#{r},#{r},0,0,1,#{r},#{r}" <>
      "v#{d}a#{r},#{r},0,0,1,-#{r},#{r}" <>
      "h-#{d}a#{r},#{r},0,0,1,-#{r},-#{r}" <>
      "v-#{d}a#{r},#{r},0,0,1,#{r},-#{r}z"
  end

  defp circle_path(cx, cy, r) do
    "M#{cx - r},#{cy}a#{r},#{r},0,1,0,#{2 * r},0a#{r},#{r},0,1,0,-#{2 * r},0z"
  end

  # -- Finder patterns --

  defp finder_module_set(dim) do
    tl = for y <- 0..8, x <- 0..8, into: MapSet.new(), do: {x, y}
    tr = for y <- 0..8, x <- (dim - 8)..(dim - 1), into: tl, do: {x, y}
    for y <- (dim - 8)..(dim - 1), x <- 0..8, into: tr, do: {x, y}
  end

  defp render_finders(dim, quiet, mod, shape, color) do
    positions = [{0, 0}, {dim - 7, 0}, {0, dim - 7}]

    paths =
      for {col, row} <- positions, into: "" do
        x = (col + quiet) * mod
        y = (row + quiet) * mod
        finder_outer_path(x, y, mod, shape) <> finder_inner_path(x, y, mod, shape)
      end

    ~s(<path d="#{paths}" fill="#{color}" fill-rule="evenodd"/>)
  end

  defp finder_outer_path(x, y, mod, :rounded) do
    s = mod * 7
    r = mod * 1.5
    ri = r * 0.5

    rounded_rect_path(x, y, s, r) <>
      rounded_rect_path(x + mod, y + mod, s - 2 * mod, ri)
  end

  defp finder_outer_path(x, y, mod, :dots) do
    s = mod * 7
    r = s / 2
    ri = r - mod
    cx = x + r
    cy = y + r
    circle_path(cx, cy, r) <> circle_path(cx, cy, ri)
  end

  defp finder_outer_path(x, y, mod, :square) do
    s = mod * 7
    i = s - 2 * mod

    "M#{x},#{y}h#{s}v#{s}h-#{s}z" <>
      "M#{x + mod},#{y + mod}v#{i}h#{i}v-#{i}z"
  end

  defp finder_inner_path(x, y, mod, :dots) do
    s = mod * 3
    circle_path(x + mod * 3.5, y + mod * 3.5, s / 2)
  end

  defp finder_inner_path(x, y, mod, :rounded) do
    s = mod * 3
    rounded_rect_path(x + mod * 2, y + mod * 2, s, mod * 0.75)
  end

  defp finder_inner_path(x, y, mod, :square) do
    s = mod * 3
    "M#{x + mod * 2},#{y + mod * 2}h#{s}v#{s}h-#{s}z"
  end

  # -- Logo --

  defp logo_placement(nil, _dim, _mod, _quiet), do: {MapSet.new(), ""}

  defp logo_placement(logo, dim, mod, quiet) do
    size = Map.get(logo, :size, 0.3)
    margin = Map.get(logo, :margin, 0)

    total_px = dim * mod
    logo_px = total_px * size
    logo_x = quiet * mod + (total_px - logo_px) / 2
    logo_y = quiet * mod + (total_px - logo_px) / 2

    hidden = hidden_modules(dim, size, margin, mod)

    bg_svg =
      case Map.get(logo, :background) do
        nil ->
          ""

        bg_color ->
          ~s(<rect x="#{logo_x - margin}" y="#{logo_y - margin}" width="#{logo_px + 2 * margin}" height="#{logo_px + 2 * margin}" fill="#{bg_color}" rx="4"/>)
      end

    content_svg =
      cond do
        Map.has_key?(logo, :svg) ->
          svg_content = Map.fetch!(logo, :svg)

          ~s(<svg x="#{logo_x}" y="#{logo_y}" width="#{logo_px}" height="#{logo_px}" viewBox="0 0 1 1">#{svg_content}</svg>)

        Map.has_key?(logo, :image_url) ->
          url = Map.fetch!(logo, :image_url)

          ~s(<image href="#{url}" x="#{logo_x}" y="#{logo_y}" width="#{logo_px}" height="#{logo_px}"/>)

        true ->
          ""
      end

    {hidden, bg_svg <> content_svg}
  end

  defp hidden_modules(dim, logo_size, margin, mod) do
    margin_modules = if mod > 0, do: ceil(margin / mod), else: 0
    start_mod = floor((dim - dim * logo_size) / 2) - margin_modules
    end_mod = ceil((dim + dim * logo_size) / 2) + margin_modules

    for r <- max(0, start_mod)..(min(dim, end_mod) - 1)//1,
        c <- max(0, start_mod)..(min(dim, end_mod) - 1)//1,
        into: MapSet.new() do
      {c, r}
    end
  end
end
