defmodule QQR.GFPolyTest do
  use ExUnit.Case, async: true

  alias QQR.GFPoly, as: Poly
  import Bitwise

  describe "new/1" do
    test "strips leading zeros" do
      assert Poly.new([0, 0, 0, 5, 3]) == [5, 3]
    end

    test "all zeros becomes [0]" do
      assert Poly.new([0, 0, 0]) == [0]
    end

    test "empty list becomes [0]" do
      assert Poly.new([]) == [0]
    end

    test "preserves non-zero leading coefficient" do
      assert Poly.new([3, 0, 1]) == [3, 0, 1]
    end
  end

  describe "degree/1" do
    test "constant polynomial has degree 0" do
      assert Poly.degree([7]) == 0
    end

    test "linear polynomial has degree 1" do
      assert Poly.degree([1, 0]) == 1
    end

    test "quadratic polynomial has degree 2" do
      assert Poly.degree([1, 2, 3]) == 2
    end

    test "zero polynomial has degree 0" do
      assert Poly.degree([0]) == 0
    end
  end

  describe "zero?/1" do
    test "zero polynomial" do
      assert Poly.zero?([0])
    end

    test "non-zero polynomial" do
      refute Poly.zero?([1, 0])
    end
  end

  describe "coefficient/2" do
    test "returns coefficient at given degree" do
      coeffs = [3, 5, 7]
      assert Poly.coefficient(coeffs, 0) == 7
      assert Poly.coefficient(coeffs, 1) == 5
      assert Poly.coefficient(coeffs, 2) == 3
    end
  end

  describe "add/2" do
    test "adding polynomial to itself yields zero" do
      p = [5, 3, 1]
      assert Poly.add(p, p) == [0]
    end

    test "adding zero is identity" do
      p = [5, 3, 1]
      assert Poly.add(p, [0]) == p
    end

    test "adds polynomials of different lengths" do
      assert Poly.add([1, 2], [3, 4, 5]) == Poly.new([3, bxor(1, 4), bxor(2, 5)])
    end
  end

  describe "multiply/2" do
    test "multiply by identity [1] returns same polynomial" do
      p = [5, 3, 1]
      assert Poly.multiply(p, [1]) == p
    end

    test "multiply by zero returns zero" do
      assert Poly.multiply([5, 3], [0]) == [0]
    end

    test "multiply two linear polynomials" do
      # (2x + 3)(4x + 5) in GF(256)
      # = 8x^2 + (10 xor 12)x + 15
      a = [2, 3]
      b = [4, 5]
      result = Poly.multiply(a, b)

      assert length(result) == 3
      assert Enum.at(result, 0) == QQR.GaloisField.multiply(2, 4)

      assert Enum.at(result, 1) ==
               bxor(QQR.GaloisField.multiply(2, 5), QQR.GaloisField.multiply(3, 4))

      assert Enum.at(result, 2) == QQR.GaloisField.multiply(3, 5)
    end
  end

  describe "multiply_scalar/2" do
    test "multiply by 0 returns zero" do
      assert Poly.multiply_scalar([5, 3], 0) == [0]
    end

    test "multiply by 1 is identity" do
      p = [5, 3, 1]
      assert Poly.multiply_scalar(p, 1) == p
    end
  end

  describe "multiply_by_monomial/3" do
    test "shifts coefficients by degree" do
      p = [5, 3]
      result = Poly.multiply_by_monomial(p, 2, 1)
      assert result == [5, 3, 0, 0]
    end

    test "multiplies coefficients by scalar" do
      p = [1]
      scalar = 7
      result = Poly.multiply_by_monomial(p, 1, scalar)
      assert result == [7, 0]
    end

    test "zero coefficient returns zero" do
      assert Poly.multiply_by_monomial([5, 3], 2, 0) == [0]
    end
  end

  describe "evaluate_at/2" do
    test "evaluate at 0 returns constant term" do
      assert Poly.evaluate_at([5, 3, 7], 0) == 7
    end

    test "evaluate at 1 returns XOR of all coefficients" do
      assert Poly.evaluate_at([5, 3, 7], 1) == bxor(bxor(5, 3), 7)
    end

    test "constant polynomial evaluates to itself" do
      assert Poly.evaluate_at([42], 100) == 42
    end

    test "evaluate linear polynomial" do
      # p(x) = 2x + 3, evaluate at x=5
      # = GF.multiply(2, 5) xor 3
      result = Poly.evaluate_at([2, 3], 5)
      assert result == bxor(QQR.GaloisField.multiply(2, 5), 3)
    end
  end
end
