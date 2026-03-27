defmodule QQR.ExtractorTest do
  use ExUnit.Case, async: true

  alias QQR.BitMatrix
  alias QQR.Extractor

  describe "square_to_quadrilateral/4" do
    test "affine case when dx3 and dy3 are zero" do
      transform = Extractor.square_to_quadrilateral({0, 0}, {10, 0}, {10, 10}, {0, 10})
      {_a11, _a12, a13, _a21, _a22, a23, _a31, _a32, _a33} = transform
      assert a13 == 0.0
      assert a23 == 0.0
    end

    test "projective case with non-zero dx3/dy3" do
      transform = Extractor.square_to_quadrilateral({0, 0}, {10, 1}, {9, 9}, {1, 10})
      {_a11, _a12, a13, _a21, _a22, a23, _a31, _a32, _a33} = transform
      refute a13 == 0.0
      refute a23 == 0.0
    end
  end

  describe "transform_point/3" do
    test "identity-like transform maps point to itself" do
      identity = {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}
      assert Extractor.transform_point(identity, 5.0, 7.0) == {5.0, 7.0}
    end

    test "translation transform" do
      translation = {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 10.0, 20.0, 1.0}
      assert Extractor.transform_point(translation, 5.0, 7.0) == {15.0, 27.0}
    end
  end

  describe "roundtrip: square_to_quadrilateral composed with quadrilateral_to_square" do
    test "is approximately identity for axis-aligned rectangle" do
      p1 = {10.0, 20.0}
      p2 = {50.0, 20.0}
      p3 = {50.0, 60.0}
      p4 = {10.0, 60.0}

      s_to_q = Extractor.square_to_quadrilateral(p1, p2, p3, p4)
      q_to_s = Extractor.quadrilateral_to_square(p1, p2, p3, p4)
      composed = Extractor.transform_multiply(s_to_q, q_to_s)

      for {x, y} <- [{0.0, 0.0}, {0.5, 0.5}, {1.0, 0.0}, {0.0, 1.0}, {1.0, 1.0}] do
        {rx, ry} = Extractor.transform_point(composed, x, y)
        assert_in_delta rx, x, 1.0e-9, "x mismatch for input {#{x}, #{y}}"
        assert_in_delta ry, y, 1.0e-9, "y mismatch for input {#{x}, #{y}}"
      end
    end

    test "is approximately identity for a projective quadrilateral" do
      p1 = {5.0, 5.0}
      p2 = {45.0, 8.0}
      p3 = {42.0, 48.0}
      p4 = {8.0, 42.0}

      s_to_q = Extractor.square_to_quadrilateral(p1, p2, p3, p4)
      q_to_s = Extractor.quadrilateral_to_square(p1, p2, p3, p4)
      composed = Extractor.transform_multiply(s_to_q, q_to_s)

      for {x, y} <- [{0.0, 0.0}, {0.3, 0.7}, {1.0, 0.0}, {0.0, 1.0}, {1.0, 1.0}] do
        {rx, ry} = Extractor.transform_point(composed, x, y)
        assert_in_delta rx, x, 1.0e-9
        assert_in_delta ry, y, 1.0e-9
      end
    end
  end

  describe "transform_multiply/2" do
    test "multiplying by identity returns same transform" do
      identity = {1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}
      t = {2.0, 3.0, 0.1, 4.0, 5.0, 0.2, 6.0, 7.0, 1.0}
      result = Extractor.transform_multiply(t, identity)

      t |> Tuple.to_list() |> Enum.zip(Tuple.to_list(result)) |> Enum.each(fn {a, b} ->
        assert_in_delta a, b, 1.0e-12
      end)
    end
  end

  describe "extract/2" do
    test "identity extraction returns same grid" do
      dim = 21
      offset = 3.5

      data =
        for y <- 0..(dim - 1), x <- 0..(dim - 1) do
          if rem(x + y, 2) == 0, do: 1, else: 0
        end

      image = BitMatrix.from_list(dim, dim, data)

      location = %{
        top_left: {offset, offset},
        top_right: {dim - offset, offset},
        bottom_left: {offset, dim - offset},
        alignment_pattern: {dim - 6.5, dim - 6.5},
        dimension: dim
      }

      {matrix, _mapping_fn} = Extractor.extract(image, location)

      for y <- 0..(dim - 1), x <- 0..(dim - 1) do
        expected = rem(x + y, 2) == 0
        assert BitMatrix.get(matrix, x, y) == expected, "mismatch at (#{x}, #{y})"
      end
    end

    test "mapping function returns image coordinates" do
      dim = 21
      scale = 3.0

      image = BitMatrix.new(round(dim * scale), round(dim * scale))

      location = %{
        top_left: {3.5 * scale, 3.5 * scale},
        top_right: {(dim - 3.5) * scale, 3.5 * scale},
        bottom_left: {3.5 * scale, (dim - 3.5) * scale},
        alignment_pattern: {(dim - 6.5) * scale, (dim - 6.5) * scale},
        dimension: dim
      }

      {_matrix, mapping_fn} = Extractor.extract(image, location)

      {x, y} = mapping_fn.(3.5, 3.5)
      assert_in_delta x, 3.5 * scale, 0.5
      assert_in_delta y, 3.5 * scale, 0.5
    end

    test "extract with scaled coordinates" do
      dim = 21
      scale = 2.0
      offset = 3.5 * scale

      data =
        for y <- 0..(dim * 2 - 1), x <- 0..(dim * 2 - 1) do
          grid_x = div(x, 2)
          grid_y = div(y, 2)
          if rem(grid_x + grid_y, 2) == 0, do: 1, else: 0
        end

      image = BitMatrix.from_list(dim * 2, dim * 2, data)

      location = %{
        top_left: {offset, offset},
        top_right: {dim * scale - offset, offset},
        bottom_left: {offset, dim * scale - offset},
        alignment_pattern: {dim * scale - 6.5 * scale, dim * scale - 6.5 * scale},
        dimension: dim
      }

      {matrix, _mapping_fn} = Extractor.extract(image, location)

      for y <- 0..(dim - 1), x <- 0..(dim - 1) do
        expected = rem(x + y, 2) == 0
        assert BitMatrix.get(matrix, x, y) == expected, "mismatch at (#{x}, #{y})"
      end
    end
  end
end
