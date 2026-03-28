defmodule QQR.SVGTest do
  use ExUnit.Case, async: true

  alias QQR.SVG

  setup do
    {:ok, matrix} = QQR.encode("Test")
    %{matrix: matrix}
  end

  describe "render/2 basics" do
    test "produces valid SVG", %{matrix: matrix} do
      svg = SVG.render(matrix)
      assert String.starts_with?(svg, "<svg")
      assert String.ends_with?(svg, "</svg>")
      assert svg =~ ~s(xmlns="http://www.w3.org/2000/svg")
    end

    test "default colors", %{matrix: matrix} do
      svg = SVG.render(matrix)
      assert svg =~ ~s(fill="#fff")
      assert svg =~ ~s(fill="#000")
    end

    test "custom colors", %{matrix: matrix} do
      svg = SVG.render(matrix, color: "#336699", background: "#f0f0f0")
      assert svg =~ ~s(fill="#f0f0f0")
      assert svg =~ ~s(fill="#336699")
    end

    test "viewBox matches dimensions", %{matrix: matrix} do
      svg = SVG.render(matrix, module_size: 5, quiet_zone: 2)
      total = (matrix.width + 4) * 5
      assert svg =~ ~s(viewBox="0 0 #{total} #{total}")
    end
  end

  describe "dot shapes" do
    test "square (default)", %{matrix: matrix} do
      svg = SVG.render(matrix, dot_shape: :square)
      assert svg =~ ~r/M\d+.*h\d+.*v\d+.*h-\d+.*z/
    end

    test "rounded", %{matrix: matrix} do
      svg = SVG.render(matrix, dot_shape: :rounded)
      assert svg =~ "a"
    end

    test "dots (circles)", %{matrix: matrix} do
      svg = SVG.render(matrix, dot_shape: :dots)
      assert svg =~ ~r/a[\d.]+,[\d.]+,0,1,0/
    end

    test "diamond", %{matrix: matrix} do
      svg = SVG.render(matrix, dot_shape: :diamond)
      assert svg =~ ~r/l[\d.]+,[\d.]+l-[\d.]+/
    end
  end

  describe "dot_size" do
    test "smaller dots produce different paths", %{matrix: matrix} do
      svg_full = SVG.render(matrix, dot_shape: :square, dot_size: 1.0)
      svg_small = SVG.render(matrix, dot_shape: :square, dot_size: 0.7)
      refute svg_full == svg_small
    end
  end

  describe "finder shapes" do
    test "rounded finder patterns", %{matrix: matrix} do
      svg = SVG.render(matrix, finder_shape: :rounded)
      assert svg =~ "fill-rule=\"evenodd\""
    end

    test "dots finder patterns", %{matrix: matrix} do
      svg = SVG.render(matrix, finder_shape: :dots)
      assert svg =~ "fill-rule=\"evenodd\""
    end

    test "dots auto-selects dots finder", %{matrix: matrix} do
      svg = SVG.render(matrix, dot_shape: :dots)
      assert svg =~ "fill-rule=\"evenodd\""
    end

    test "square dot with square finder has no evenodd", %{matrix: matrix} do
      svg = SVG.render(matrix, dot_shape: :square, finder_shape: :square)
      refute svg =~ "fill-rule=\"evenodd\""
    end
  end

  describe "logo embedding" do
    test "embeds inline SVG logo", %{matrix: matrix} do
      logo = %{svg: ~s(<circle r="0.4" cx="0.5" cy="0.5" fill="red"/>), size: 0.25}
      svg = SVG.render(matrix, logo: logo)
      assert svg =~ "<circle"
      assert svg =~ "viewBox=\"0 0 1 1\""
    end

    test "embeds image URL logo", %{matrix: matrix} do
      logo = %{image_url: "data:image/png;base64,abc123", size: 0.2}
      svg = SVG.render(matrix, logo: logo)
      assert svg =~ "<image"
      assert svg =~ "data:image/png;base64,abc123"
    end

    test "logo with background", %{matrix: matrix} do
      logo = %{svg: "<rect/>", size: 0.3, background: "#fff"}
      svg = SVG.render(matrix, logo: logo)
      assert svg =~ ~s(fill="#fff" rx="4")
    end

    test "logo clears center modules", %{matrix: matrix} do
      svg_no_logo = SVG.render(matrix)
      svg_logo = SVG.render(matrix, logo: %{svg: "<rect/>", size: 0.3})
      assert byte_size(svg_no_logo) > byte_size(svg_logo)
    end
  end

  describe "BitMatrix.to_svg/2 delegation" do
    test "delegates to SVG.render", %{matrix: matrix} do
      direct = SVG.render(matrix, dot_shape: :dots)
      delegated = QQR.BitMatrix.to_svg(matrix, dot_shape: :dots)
      assert direct == delegated
    end
  end
end
