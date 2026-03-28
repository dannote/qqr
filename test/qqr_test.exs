defmodule QQRTest do
  use ExUnit.Case

  test "decode_matrix returns error for nil" do
    assert :error = QQR.decode_matrix(nil)
  end

  describe "decode/4 input validation" do
    test "raises ArgumentError for zero width" do
      assert_raise ArgumentError, ~r/width and height must be positive/, fn ->
        QQR.decode(<<0, 0, 0, 0>>, 0, 1)
      end
    end

    test "raises ArgumentError for zero height" do
      assert_raise ArgumentError, ~r/width and height must be positive/, fn ->
        QQR.decode(<<0, 0, 0, 0>>, 1, 0)
      end
    end

    test "raises ArgumentError for negative dimensions" do
      assert_raise ArgumentError, ~r/width and height must be positive/, fn ->
        QQR.decode(<<0, 0, 0, 0>>, -1, 1)
      end
    end

    test "raises ArgumentError for wrong RGBA size" do
      assert_raise ArgumentError, ~r/expected 16 bytes.*got: 4/, fn ->
        QQR.decode(<<0, 0, 0, 0>>, 2, 2)
      end
    end
  end

  describe "BitMatrix.from_list/3 input validation" do
    test "raises ArgumentError for mismatched list length" do
      assert_raise ArgumentError, ~r/list length 3 does not match 2x2/, fn ->
        QQR.BitMatrix.from_list(2, 2, [0, 1, 0])
      end
    end
  end
end
