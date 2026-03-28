defmodule QQR.GFPoly do
  @moduledoc """
  Polynomials over GF(256), represented as coefficient lists from highest to lowest degree.

  Lists are normalized on construction: leading zeros are stripped so
  `degree/1` always equals `length - 1`. The zero polynomial is `[0]`.
  """

  alias QQR.GaloisField, as: GF
  import Bitwise

  def new([]), do: [0]

  def new([0 | _] = coeffs) do
    case Enum.drop_while(coeffs, &(&1 == 0)) do
      [] -> [0]
      normalized -> normalized
    end
  end

  def new(coeffs), do: coeffs

  def zero?(coeffs), do: hd(coeffs) == 0

  def degree(coeffs), do: length(coeffs) - 1

  def coefficient(coeffs, deg), do: Enum.at(coeffs, length(coeffs) - 1 - deg)

  def add(a, b) do
    {short, long} = if length(a) > length(b), do: {b, a}, else: {a, b}
    diff = length(long) - length(short)
    padded = List.duplicate(0, diff) ++ short
    Enum.zip_with(long, padded, &bxor/2) |> new()
  end

  def multiply_scalar(_coeffs, 0), do: [0]
  def multiply_scalar(coeffs, 1), do: coeffs

  def multiply_scalar(coeffs, scalar) do
    Enum.map(coeffs, &GF.multiply(&1, scalar)) |> new()
  end

  def multiply([0], _), do: [0]
  def multiply(_, [0]), do: [0]

  def multiply(a, b) do
    product = List.duplicate(0, length(a) + length(b) - 1)

    a
    |> Enum.with_index()
    |> Enum.reduce(product, fn {a_coeff, i}, prod ->
      b
      |> Enum.with_index()
      |> Enum.reduce(prod, fn {b_coeff, j}, p ->
        List.update_at(p, i + j, &bxor(&1, GF.multiply(a_coeff, b_coeff)))
      end)
    end)
    |> new()
  end

  def multiply_by_monomial(_coeffs, _degree, 0), do: [0]

  def multiply_by_monomial(coeffs, deg, coeff) do
    (Enum.map(coeffs, &GF.multiply(&1, coeff)) ++ List.duplicate(0, deg))
    |> new()
  end

  def evaluate_at(coeffs, 0), do: coefficient(coeffs, 0)
  def evaluate_at(coeffs, 1), do: Enum.reduce(coeffs, 0, &bxor/2)

  def evaluate_at([first | rest], a) do
    Enum.reduce(rest, first, fn c, result ->
      bxor(GF.multiply(a, result), c)
    end)
  end
end
