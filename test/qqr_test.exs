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

  describe "encode/2 option validation" do
    test "raises on unknown option" do
      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", foo: :bar)
      end
    end

    test "raises on invalid ec_level" do
      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", ec_level: :max)
      end
    end

    test "raises on invalid mode" do
      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", mode: :utf8)
      end
    end

    test "raises on invalid version" do
      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", version: 0)
      end

      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", version: 41)
      end
    end

    test "raises on invalid mask" do
      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", mask: -1)
      end

      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.encode("hello", mask: 8)
      end
    end

    test "accepts valid options" do
      assert {:ok, _} = QQR.encode("hello", ec_level: :high, mode: :byte, version: 2, mask: 3)
    end
  end

  describe "to_svg/2 option validation" do
    test "raises on invalid encode option" do
      assert_raise ArgumentError, ~r/invalid encode option/, fn ->
        QQR.to_svg("hello", ec_level: :max)
      end
    end

    test "passes through unknown options as SVG options" do
      assert is_binary(QQR.to_svg("hello", dot_shape: :rounded))
    end
  end

  describe "decode/4 option validation" do
    test "raises on unknown option" do
      pixel = <<0, 0, 0, 255>>

      assert_raise ArgumentError, ~r/invalid decode option/, fn ->
        QQR.decode(pixel, 1, 1, foo: :bar)
      end
    end

    test "raises on invalid inversion value" do
      pixel = <<0, 0, 0, 255>>

      assert_raise ArgumentError, ~r/invalid decode option/, fn ->
        QQR.decode(pixel, 1, 1, inversion: :yes)
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
