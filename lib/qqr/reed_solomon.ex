defmodule QQR.ReedSolomon do
  @moduledoc false

  alias QQR.GaloisField, as: GF
  alias QQR.GFPoly
  import Bitwise

  def decode(bytes, num_ec_codewords) when is_list(bytes) do
    two_s = num_ec_codewords
    poly = GFPoly.new(bytes)

    syndrome_coeffs =
      for s <- (two_s - 1)..0//-1, do: GFPoly.evaluate_at(poly, GF.exp(s))

    if Enum.all?(syndrome_coeffs, &(&1 == 0)) do
      {:ok, bytes}
    else
      syndrome = GFPoly.new(syndrome_coeffs)
      a = [1 | List.duplicate(0, two_s)]

      with {:ok, {sigma, omega}} <- run_euclidean(a, syndrome, two_s),
           {:ok, locations} <- find_error_locations(sigma),
           magnitudes = find_error_magnitudes(omega, locations),
           {:ok, corrected} <- apply_corrections(bytes, locations, magnitudes) do
        {:ok, corrected}
      end
    end
  end

  defp run_euclidean(a, b, r) do
    {a, b} = if GFPoly.degree(a) < GFPoly.degree(b), do: {b, a}, else: {a, b}

    r_last = a
    r_curr = b
    t_last = [0]
    t_curr = [1]

    euclidean_loop(r_last, r_curr, t_last, t_curr, r)
  end

  defp euclidean_loop(r_last, r_curr, t_last, t_curr, r) do
    if GFPoly.degree(r_curr) < div(r, 2) do
      normalize(t_curr, r_curr)
    else
      if GFPoly.zero?(r_curr) do
        :error
      else
        {q, remainder} = poly_divide(r_last, r_curr)
        t_new = GFPoly.add(GFPoly.multiply(q, t_curr), t_last)

        if GFPoly.degree(remainder) >= GFPoly.degree(r_curr) do
          :error
        else
          euclidean_loop(r_curr, remainder, t_curr, t_new, r)
        end
      end
    end
  end

  defp poly_divide(dividend, divisor) do
    lead_term = hd(divisor)
    lead_inverse = GF.inverse(lead_term)
    do_poly_divide(dividend, divisor, lead_inverse, [0])
  end

  defp do_poly_divide(remainder, divisor, lead_inverse, quotient) do
    if GFPoly.degree(remainder) < GFPoly.degree(divisor) or GFPoly.zero?(remainder) do
      {GFPoly.new(quotient), remainder}
    else
      degree_diff = GFPoly.degree(remainder) - GFPoly.degree(divisor)
      scale = GF.multiply(hd(remainder), lead_inverse)
      mono = [scale | List.duplicate(0, degree_diff)]
      quotient = GFPoly.add(quotient, mono)
      subtracted = GFPoly.multiply_by_monomial(divisor, degree_diff, scale)
      remainder = GFPoly.add(remainder, subtracted)
      do_poly_divide(remainder, divisor, lead_inverse, quotient)
    end
  end

  defp normalize(sigma, omega) do
    sigma_at_zero = GFPoly.coefficient(sigma, 0)

    if sigma_at_zero == 0 do
      :error
    else
      inv = GF.inverse(sigma_at_zero)
      {:ok, {GFPoly.multiply_scalar(sigma, inv), GFPoly.multiply_scalar(omega, inv)}}
    end
  end

  defp find_error_locations(error_locator) do
    num_errors = GFPoly.degree(error_locator)

    if num_errors == 1 do
      {:ok, [GFPoly.coefficient(error_locator, 1)]}
    else
      {locations, _} =
        Enum.reduce_while(1..255, {[], 0}, fn i, {locs, count} ->
          if count == num_errors do
            {:halt, {locs, count}}
          else
            if GFPoly.evaluate_at(error_locator, i) == 0 do
              {:cont, {[GF.inverse(i) | locs], count + 1}}
            else
              {:cont, {locs, count}}
            end
          end
        end)

      if length(locations) == num_errors do
        {:ok, Enum.reverse(locations)}
      else
        :error
      end
    end
  end

  defp find_error_magnitudes(error_evaluator, error_locations) do
    error_locations
    |> Enum.with_index()
    |> Enum.map(fn {loc_i, i} ->
      xi_inverse = GF.inverse(loc_i)

      denominator =
        error_locations
        |> Enum.with_index()
        |> Enum.reduce(1, fn {loc_j, j}, acc ->
          if i == j, do: acc, else: GF.multiply(acc, bxor(1, GF.multiply(loc_j, xi_inverse)))
        end)

      GF.multiply(GFPoly.evaluate_at(error_evaluator, xi_inverse), GF.inverse(denominator))
    end)
  end

  defp apply_corrections(bytes, locations, magnitudes) do
    len = length(bytes)

    Enum.zip(locations, magnitudes)
    |> Enum.reduce_while({:ok, bytes}, fn {location, magnitude}, {:ok, acc} ->
      position = len - 1 - GF.log(location)

      if position < 0 or position >= len do
        {:halt, :error}
      else
        corrected = List.update_at(acc, position, &bxor(&1, magnitude))
        {:cont, {:ok, corrected}}
      end
    end)
  end
end
