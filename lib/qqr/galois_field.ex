defmodule QQR.GaloisField do
  @moduledoc """
  GF(256) arithmetic using primitive polynomial 0x011D.

  Exp/log lookup tables are compiled into function heads at build time,
  giving O(1) dispatch for multiply, inverse, and exponentiation.
  """

  import Bitwise

  @primitive_polynomial 0x011D
  @field_size 256

  {exp_table, log_table} =
    Enum.reduce(0..(@field_size - 1), {%{}, %{}, 1}, fn i, {exp, log, x} ->
      exp = Map.put(exp, i, x)
      log = if i < @field_size - 1, do: Map.put(log, x, i), else: log

      next = x <<< 1
      next = if next >= @field_size, do: bxor(next, @primitive_polynomial), else: next

      {exp, log, next}
    end)
    |> then(fn {exp, log, _} -> {exp, log} end)

  for {i, val} <- exp_table do
    def exp(unquote(i)), do: unquote(val)
  end

  for {val, i} <- log_table do
    def log(unquote(val)), do: unquote(i)
  end

  def log(0), do: raise("Cannot take log(0)")

  def add(a, b), do: bxor(a, b)

  def multiply(0, _), do: 0
  def multiply(_, 0), do: 0
  def multiply(a, b), do: exp(rem(log(a) + log(b), @field_size - 1))

  def inverse(0), do: raise("Cannot invert 0")
  def inverse(a), do: exp(@field_size - 1 - log(a))
end
