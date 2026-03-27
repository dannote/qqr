defmodule QQR.BitMatrixTest do
  use ExUnit.Case, async: true

  alias QQR.BitMatrix

  describe "new/2" do
    test "creates a matrix of the given dimensions with all bits false" do
      m = BitMatrix.new(3, 4)
      assert m.width == 3
      assert m.height == 4
      assert tuple_size(m.data) == 12

      for x <- 0..2, y <- 0..3 do
        refute BitMatrix.get(m, x, y)
      end
    end

    test "creates a 1x1 matrix" do
      m = BitMatrix.new(1, 1)
      assert m.width == 1
      assert m.height == 1
      refute BitMatrix.get(m, 0, 0)
    end
  end

  describe "from_list/3" do
    test "creates a matrix from a flat list" do
      m = BitMatrix.from_list(2, 2, [1, 0, 0, 1])
      assert BitMatrix.get(m, 0, 0) == true
      assert BitMatrix.get(m, 1, 0) == false
      assert BitMatrix.get(m, 0, 1) == false
      assert BitMatrix.get(m, 1, 1) == true
    end
  end

  describe "get/3" do
    test "returns the correct value for in-bounds coordinates" do
      m = BitMatrix.new(5, 5) |> BitMatrix.set(2, 3, true)
      assert BitMatrix.get(m, 2, 3) == true
      assert BitMatrix.get(m, 0, 0) == false
    end

    test "returns false for negative coordinates" do
      m = BitMatrix.new(5, 5)
      assert BitMatrix.get(m, -1, 0) == false
      assert BitMatrix.get(m, 0, -1) == false
    end

    test "returns false for coordinates beyond width/height" do
      m = BitMatrix.new(5, 5)
      assert BitMatrix.get(m, 5, 0) == false
      assert BitMatrix.get(m, 0, 5) == false
      assert BitMatrix.get(m, 100, 100) == false
    end
  end

  describe "set/4" do
    test "sets a bit to true" do
      m = BitMatrix.new(3, 3) |> BitMatrix.set(1, 2, true)
      assert BitMatrix.get(m, 1, 2) == true
    end

    test "sets a bit back to false" do
      m =
        BitMatrix.new(3, 3)
        |> BitMatrix.set(1, 1, true)
        |> BitMatrix.set(1, 1, false)

      assert BitMatrix.get(m, 1, 1) == false
    end

    test "does not mutate the original matrix" do
      original = BitMatrix.new(3, 3)
      _modified = BitMatrix.set(original, 0, 0, true)
      assert BitMatrix.get(original, 0, 0) == false
    end
  end

  describe "set_region/6" do
    test "sets a rectangular region to true" do
      m = BitMatrix.new(5, 5) |> BitMatrix.set_region(1, 1, 3, 2, true)

      for x <- 1..3, y <- 1..2 do
        assert BitMatrix.get(m, x, y), "expected (#{x}, #{y}) to be true"
      end

      refute BitMatrix.get(m, 0, 0)
      refute BitMatrix.get(m, 4, 4)
      refute BitMatrix.get(m, 1, 0)
      refute BitMatrix.get(m, 1, 3)
    end

    test "sets a region back to false" do
      m =
        BitMatrix.new(5, 5)
        |> BitMatrix.set_region(0, 0, 5, 5, true)
        |> BitMatrix.set_region(1, 1, 3, 3, false)

      assert BitMatrix.get(m, 0, 0) == true
      assert BitMatrix.get(m, 4, 4) == true
      assert BitMatrix.get(m, 2, 2) == false
    end

    test "handles zero-width or zero-height region" do
      m = BitMatrix.new(3, 3)
      assert BitMatrix.set_region(m, 0, 0, 0, 3, true) == m
      assert BitMatrix.set_region(m, 0, 0, 3, 0, true) == m
    end

    test "handles single-cell region" do
      m = BitMatrix.new(3, 3) |> BitMatrix.set_region(1, 1, 1, 1, true)
      assert BitMatrix.get(m, 1, 1) == true
      refute BitMatrix.get(m, 0, 0)
      refute BitMatrix.get(m, 2, 2)
    end

    test "handles full-matrix region" do
      m = BitMatrix.new(4, 4) |> BitMatrix.set_region(0, 0, 4, 4, true)

      for x <- 0..3, y <- 0..3 do
        assert BitMatrix.get(m, x, y)
      end
    end
  end
end
