defmodule QQR.ReedSolomonTest do
  use ExUnit.Case, async: true

  alias QQR.GaloisField, as: GF
  alias QQR.GFPoly
  alias QQR.ReedSolomon
  import Bitwise

  # QR Version 1-M uses RS(26, 16) — 16 data + 10 EC codewords
  # This is a real codeblock from a QR code encoding "Hello"
  @data_codewords [32, 86, 134, 198, 198, 242, 194, 4, 236, 17, 236, 17, 236, 17, 236, 17]

  # Generate EC codewords using the generator polynomial for 10 EC codewords
  # Generator for nsym=10: product of (x - α^i) for i=0..9
  defp rs_encode(data, num_ec) do
    gen = generator_poly(num_ec)
    # Shift data polynomial by num_ec positions
    padded = data ++ List.duplicate(0, num_ec)

    # Polynomial long division: padded / gen, remainder is EC
    remainder = poly_mod(padded, gen)

    # Pad remainder to num_ec length
    remainder = List.duplicate(0, num_ec - length(remainder)) ++ remainder
    data ++ remainder
  end

  defp generator_poly(num_ec) do
    Enum.reduce(0..(num_ec - 1), [1], fn i, gen ->
      GFPoly.multiply(gen, [1, GF.exp(i)])
    end)
  end

  defp poly_mod(dividend, divisor) do
    Enum.reduce(0..(length(dividend) - length(divisor)), dividend, fn i, rem_poly ->
      coeff = Enum.at(rem_poly, i)
      if coeff != 0, do: poly_mod_step(rem_poly, divisor, coeff, i), else: rem_poly
    end)
    |> Enum.drop(length(dividend) - length(divisor) + 1)
  end

  defp poly_mod_step(rem_poly, divisor, coeff, offset) do
    Enum.with_index(divisor)
    |> Enum.reduce(rem_poly, fn {d, j}, acc ->
      List.update_at(acc, offset + j, &bxor(&1, GF.multiply(d, coeff)))
    end)
  end

  setup_all do
    encoded = rs_encode(@data_codewords, 10)
    %{encoded: encoded, num_ec: 10}
  end

  test "no errors returns same bytes", %{encoded: encoded, num_ec: num_ec} do
    assert {:ok, ^encoded} = ReedSolomon.decode(encoded, num_ec)
  end

  test "single byte error is corrected", %{encoded: encoded, num_ec: num_ec} do
    corrupted = List.replace_at(encoded, 3, bxor(Enum.at(encoded, 3), 0x55))
    assert {:ok, result} = ReedSolomon.decode(corrupted, num_ec)
    assert result == encoded
  end

  test "error in EC codeword region is corrected", %{encoded: encoded, num_ec: num_ec} do
    pos = length(encoded) - 2
    corrupted = List.replace_at(encoded, pos, bxor(Enum.at(encoded, pos), 0xAB))
    assert {:ok, result} = ReedSolomon.decode(corrupted, num_ec)
    assert result == encoded
  end

  test "multiple errors within correction capacity", %{encoded: encoded, num_ec: num_ec} do
    # RS(26,16) with 10 EC codewords can correct up to 5 errors
    corrupted =
      encoded
      |> List.replace_at(0, bxor(Enum.at(encoded, 0), 0xFF))
      |> List.replace_at(5, bxor(Enum.at(encoded, 5), 0x33))
      |> List.replace_at(10, bxor(Enum.at(encoded, 10), 0x77))

    assert {:ok, result} = ReedSolomon.decode(corrupted, num_ec)
    assert result == encoded
  end

  test "maximum correctable errors (t=5)", %{encoded: encoded, num_ec: num_ec} do
    corrupted =
      encoded
      |> List.replace_at(1, bxor(Enum.at(encoded, 1), 0x01))
      |> List.replace_at(7, bxor(Enum.at(encoded, 7), 0xFE))
      |> List.replace_at(12, bxor(Enum.at(encoded, 12), 0x42))
      |> List.replace_at(18, bxor(Enum.at(encoded, 18), 0x99))
      |> List.replace_at(24, bxor(Enum.at(encoded, 24), 0xAA))

    assert {:ok, result} = ReedSolomon.decode(corrupted, num_ec)
    assert result == encoded
  end

  test "too many errors returns :error", %{encoded: encoded, num_ec: num_ec} do
    # 6 errors exceeds the capacity of t=5
    corrupted =
      encoded
      |> List.replace_at(0, bxor(Enum.at(encoded, 0), 0xFF))
      |> List.replace_at(3, bxor(Enum.at(encoded, 3), 0x33))
      |> List.replace_at(7, bxor(Enum.at(encoded, 7), 0x77))
      |> List.replace_at(11, bxor(Enum.at(encoded, 11), 0xAA))
      |> List.replace_at(15, bxor(Enum.at(encoded, 15), 0xCC))
      |> List.replace_at(20, bxor(Enum.at(encoded, 20), 0x11))

    assert ReedSolomon.decode(corrupted, num_ec) == :error
  end

  test "first byte error", %{encoded: encoded, num_ec: num_ec} do
    corrupted = List.replace_at(encoded, 0, bxor(Enum.at(encoded, 0), 0x01))
    assert {:ok, result} = ReedSolomon.decode(corrupted, num_ec)
    assert result == encoded
  end

  test "last byte error", %{encoded: encoded, num_ec: num_ec} do
    last = length(encoded) - 1
    corrupted = List.replace_at(encoded, last, bxor(Enum.at(encoded, last), 0x80))
    assert {:ok, result} = ReedSolomon.decode(corrupted, num_ec)
    assert result == encoded
  end

  test "works with different EC codeword counts" do
    data = [64, 196, 132, 84, 20, 236, 17, 236, 17]
    encoded = rs_encode(data, 17)
    corrupted = List.replace_at(encoded, 4, bxor(Enum.at(encoded, 4), 0xDE))
    assert {:ok, result} = ReedSolomon.decode(corrupted, 17)
    assert result == encoded
  end
end
