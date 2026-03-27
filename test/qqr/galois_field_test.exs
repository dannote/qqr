defmodule QQR.GaloisFieldTest do
  use ExUnit.Case, async: true

  alias QQR.GaloisField, as: GF

  describe "exp/1 known values" do
    test "exp(0) = 1" do
      assert GF.exp(0) == 1
    end

    test "exp(1) = 2" do
      assert GF.exp(1) == 2
    end

    test "exp(7) = 128" do
      assert GF.exp(7) == 128
    end

    test "exp(8) = 29 (256 XOR 0x11D)" do
      assert GF.exp(8) == 29
    end
  end

  describe "exp/log roundtrip" do
    test "log(exp(i)) == i for all 0..254" do
      for i <- 0..254 do
        assert GF.log(GF.exp(i)) == i, "failed for i=#{i}"
      end
    end

    test "exp(log(a)) == a for all 1..255" do
      for a <- 1..255 do
        assert GF.exp(GF.log(a)) == a, "failed for a=#{a}"
      end
    end
  end

  describe "add/2" do
    test "is XOR" do
      assert GF.add(0b1010, 0b0110) == 0b1100
      assert GF.add(0xFF, 0xFF) == 0
      assert GF.add(42, 0) == 42
    end
  end

  describe "multiply/2" do
    test "identity: a * 1 = a for all 0..255" do
      for a <- 0..255 do
        assert GF.multiply(a, 1) == a, "failed for a=#{a}"
      end
    end

    test "zero: a * 0 = 0" do
      for a <- 0..255 do
        assert GF.multiply(a, 0) == 0
      end
    end

    test "commutativity: a * b = b * a" do
      for a <- 1..50, b <- 1..50 do
        assert GF.multiply(a, b) == GF.multiply(b, a),
               "failed for a=#{a}, b=#{b}"
      end
    end
  end

  describe "inverse/1" do
    test "a * inverse(a) = 1 for all 1..255" do
      for a <- 1..255 do
        assert GF.multiply(a, GF.inverse(a)) == 1, "failed for a=#{a}"
      end
    end

    test "raises on 0" do
      assert_raise RuntimeError, "Cannot invert 0", fn ->
        GF.inverse(0)
      end
    end
  end

  describe "log/1" do
    test "raises on 0" do
      assert_raise RuntimeError, "Cannot take log(0)", fn ->
        GF.log(0)
      end
    end
  end
end
