defmodule QQR.LocatorTest do
  use ExUnit.Case, async: true

  alias QQR.BitMatrix
  alias QQR.Locator

  defp build_qr_matrix do
    size = 29
    m = BitMatrix.new(size, size)

    m = draw_finder_pattern(m, 0, 0)
    m = draw_finder_pattern(m, 22, 0)
    m = draw_finder_pattern(m, 0, 22)

    m = draw_alignment_pattern(m, 24, 24)

    m
  end

  defp draw_finder_pattern(m, left, top) do
    m
    |> BitMatrix.set_region(left, top, 7, 7, true)
    |> BitMatrix.set_region(left + 1, top + 1, 5, 5, false)
    |> BitMatrix.set_region(left + 2, top + 2, 3, 3, true)
  end

  defp draw_alignment_pattern(m, cx, cy) do
    m
    |> BitMatrix.set_region(cx - 2, cy - 2, 5, 5, true)
    |> BitMatrix.set_region(cx - 1, cy - 1, 3, 3, false)
    |> BitMatrix.set(cx, cy, true)
  end

  describe "locate/1" do
    test "returns nil for a blank matrix" do
      m = BitMatrix.new(50, 50)
      assert Locator.locate(m) == nil
    end

    test "returns nil for a solid black matrix" do
      m = BitMatrix.new(50, 50) |> BitMatrix.set_region(0, 0, 50, 50, true)
      assert Locator.locate(m) == nil
    end

    test "finds patterns in a synthetic QR image" do
      m = build_qr_matrix()
      result = Locator.locate(m)

      assert [location | _] = result

      assert Map.has_key?(location, :top_left)
      assert Map.has_key?(location, :top_right)
      assert Map.has_key?(location, :bottom_left)
      assert Map.has_key?(location, :alignment)
      assert Map.has_key?(location, :dimension)

      {tl_x, tl_y} = location.top_left
      {tr_x, tr_y} = location.top_right
      {bl_x, bl_y} = location.bottom_left

      assert tl_x < tr_x, "top_left should be left of top_right"
      assert tl_y < bl_y, "top_left should be above bottom_left"

      assert abs(tl_y - tr_y) < 5, "top_left and top_right should be at similar y"
      assert abs(tl_x - bl_x) < 5, "top_left and bottom_left should be at similar x"

      assert location.dimension > 0
      assert rem(location.dimension, 4) == 1
    end

    test "finds patterns in a scaled-up QR image" do
      scale = 3
      size = 29 * scale
      m = BitMatrix.new(size, size)

      m = draw_scaled_finder(m, 0, 0, scale)
      m = draw_scaled_finder(m, 22 * scale, 0, scale)
      m = draw_scaled_finder(m, 0, 22 * scale, scale)

      result = Locator.locate(m)

      assert [location | _] = result
      assert location.dimension > 0
    end
  end

  describe "reorder_finder_patterns/3" do
    test "identifies top_left as the point farthest from the other two" do
      top_left = {0.0, 0.0}
      top_right = {20.0, 0.0}
      bottom_left = {0.0, 20.0}

      {tl, tr, bl} = Locator.reorder_finder_patterns(top_left, top_right, bottom_left)
      assert tl == top_left
      assert tr == top_right
      assert bl == bottom_left
    end

    test "handles points in any order" do
      top_left = {0.0, 0.0}
      top_right = {20.0, 0.0}
      bottom_left = {0.0, 20.0}

      {tl1, tr1, bl1} = Locator.reorder_finder_patterns(bottom_left, top_left, top_right)
      assert tl1 == top_left
      assert tr1 == top_right
      assert bl1 == bottom_left

      {tl2, tr2, bl2} = Locator.reorder_finder_patterns(top_right, bottom_left, top_left)
      assert tl2 == top_left
      assert tr2 == top_right
      assert bl2 == bottom_left
    end

    test "uses cross product to distinguish top_right from bottom_left" do
      {tl, tr, bl} = Locator.reorder_finder_patterns({10.0, 0.0}, {10.0, 10.0}, {0.0, 0.0})

      {tl_x, tl_y} = tl
      {tr_x, tr_y} = tr
      {bl_x, bl_y} = bl

      cross = (tr_x - tl_x) * (bl_y - tl_y) - (tr_y - tl_y) * (bl_x - tl_x)
      assert cross >= 0
    end

    test "works with equilateral-like triangle" do
      p1 = {5.0, 0.0}
      p2 = {0.0, 8.66}
      p3 = {10.0, 8.66}

      {tl, _tr, _bl} = Locator.reorder_finder_patterns(p1, p2, p3)

      assert tl == p1
    end
  end

  defp draw_scaled_finder(m, left, top, scale) do
    m
    |> BitMatrix.set_region(left, top, 7 * scale, 7 * scale, true)
    |> BitMatrix.set_region(left + scale, top + scale, 5 * scale, 5 * scale, false)
    |> BitMatrix.set_region(left + 2 * scale, top + 2 * scale, 3 * scale, 3 * scale, true)
  end
end
