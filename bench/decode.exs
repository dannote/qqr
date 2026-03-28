Mix.install([
  {:qqr, path: "."},
  {:qr_code, "~> 3.0"},
  {:qrex, "~> 0.1.0"},
  {:benchee, "~> 1.5"}
])

defmodule BenchHelper do
  @scale 4
  @quiet 4

  def build_images(text) do
    {:ok, qr} = QRCode.create(text, :medium)
    matrix = qr.matrix
    dim = length(matrix)
    img_dim = (dim + @quiet * 2) * @scale

    grid =
      matrix
      |> List.flatten()
      |> then(&QQR.BitMatrix.from_list(dim, dim, &1))

    rgba = build_rgba(matrix, dim, img_dim)

    png = build_png(rgba, img_dim)

    %{grid: grid, rgba: rgba, png: png, dim: img_dim, version: qr.version}
  end

  defp build_rgba(matrix, _dim, img_dim) do
    quiet_row = :binary.copy(<<255, 255, 255, 255>>, img_dim)
    quiet_px = :binary.copy(<<255, 255, 255, 255>>, @quiet * @scale)

    top = :binary.copy(quiet_row, @quiet * @scale)

    data =
      for row <- matrix, _sy <- 1..@scale, into: <<>> do
        rpx =
          for cell <- row, _sx <- 1..@scale, into: <<>> do
            if cell == 1, do: <<0, 0, 0, 255>>, else: <<255, 255, 255, 255>>
          end

        quiet_px <> rpx <> quiet_px
      end

    bottom = :binary.copy(quiet_row, @quiet * @scale)
    top <> data <> bottom
  end

  defp build_png(rgba, img_dim) do
    rgb = for <<r, g, b, _a <- rgba>>, into: <<>>, do: <<r, g, b>>

    Pngex.new(type: :rgb, depth: :depth8, width: img_dim, height: img_dim)
    |> Pngex.generate(rgb)
    |> IO.iodata_to_binary()
  end
end

cases = [
  {"v1_short", "Hello"},
  {"v3_url", "https://elixir-lang.org"},
  {"v7_long", String.duplicate("ABCDEFGHIJ", 10)}
]

inputs =
  Map.new(cases, fn {name, text} ->
    data = BenchHelper.build_images(text)
    IO.puts("#{name} (v#{data.version}, #{data.dim}×#{data.dim})")
    {name, Map.put(data, :text, text)}
  end)

for {name, %{rgba: rgba, dim: dim, grid: grid, png: png, text: text}} <- inputs do
  {:ok, r1} = QQR.decode_matrix(grid)
  {:ok, r2} = QQR.decode(rgba, dim, dim, inversion: :dont_invert)
  {:ok, [{:ok, r3}]} = QRex.detect_qr_codes(png)
  ^text = r1.text
  ^text = r2.text
  ^text = r3.text
  IO.puts("  #{name}: ✓")
end

IO.puts("")

Benchee.run(
  %{
    "QQR.decode_matrix" => fn %{grid: grid} ->
      QQR.decode_matrix(grid)
    end,
    "QQR.decode (RGBA)" => fn %{rgba: rgba, dim: dim} ->
      QQR.decode(rgba, dim, dim, inversion: :dont_invert)
    end,
    "QRex (Rust NIF, PNG)" => fn %{png: png} ->
      QRex.detect_qr_codes(png)
    end
  },
  inputs: inputs,
  warmup: 3,
  time: 5,
  print: [configuration: false]
)
