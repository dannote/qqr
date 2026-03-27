defmodule QQR.BinarizerTest do
  use ExUnit.Case, async: true

  alias QQR.{Binarizer, BitMatrix}

  @white_pixel <<255, 255, 255, 255>>
  @black_pixel <<0, 0, 0, 255>>

  defp uniform_image(pixel, width, height) do
    String.duplicate(pixel, width * height)
  end

  defp all_values(matrix) do
    for y <- 0..(matrix.height - 1), x <- 0..(matrix.width - 1), do: BitMatrix.get(matrix, x, y)
  end

  describe "binarize/4" do
    test "all-white image produces all-false matrix" do
      {matrix, nil} = Binarizer.binarize(uniform_image(@white_pixel, 16, 16), 16, 16)

      assert Enum.all?(all_values(matrix), &(not &1))
    end

    test "all-black image produces all-true matrix" do
      {matrix, nil} = Binarizer.binarize(uniform_image(@black_pixel, 16, 16), 16, 16)

      assert Enum.all?(all_values(matrix), & &1)
    end

    test "black square on white background is detected" do
      size = 24

      rgba =
        for y <- 0..(size - 1), x <- 0..(size - 1), into: <<>> do
          if x >= 8 and x < 16 and y >= 8 and y < 16, do: @black_pixel, else: @white_pixel
        end

      {matrix, nil} = Binarizer.binarize(rgba, size, size)

      for y <- 8..15, x <- 8..15 do
        assert BitMatrix.get(matrix, x, y),
               "expected black at (#{x}, #{y})"
      end

      corners = [{0, 0}, {23, 0}, {0, 23}, {23, 23}]

      for {x, y} <- corners do
        refute BitMatrix.get(matrix, x, y),
               "expected white at (#{x}, #{y})"
      end
    end

    test "inversion flag produces inverted output" do
      {normal, inverted} =
        Binarizer.binarize(uniform_image(@black_pixel, 16, 16), 16, 16, invert: true)

      assert inverted != nil

      for y <- 0..15, x <- 0..15 do
        assert BitMatrix.get(normal, x, y) != BitMatrix.get(inverted, x, y)
      end
    end

    test "non-multiple-of-8 dimensions work" do
      {matrix, nil} = Binarizer.binarize(uniform_image(@white_pixel, 10, 10), 10, 10)

      assert matrix.width == 10
      assert matrix.height == 10
    end
  end

  describe "grayscale conversion" do
    test "pure red produces correct luminance" do
      pixel = <<255, 0, 0, 255>>
      {matrix, nil} = Binarizer.binarize(String.duplicate(pixel, 16 * 16), 16, 16)
      assert is_struct(matrix, BitMatrix)
    end

    test "known gray value is computed correctly" do
      r = 100
      g = 150
      b = 200
      expected_lum = trunc(0.2126 * r + 0.7152 * g + 0.0722 * b)

      assert expected_lum == 142
    end
  end
end
