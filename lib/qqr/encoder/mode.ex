defmodule QQR.Encoder.Mode do
  @moduledoc false

  import Bitwise

  alias QQR.Encoder.Tables

  def detect_mode(text) do
    cond do
      numeric?(text) -> :numeric
      alphanumeric?(text) -> :alphanumeric
      true -> :byte
    end
  end

  def select_mode(text, nil), do: detect_mode(text)
  def select_mode(_text, mode), do: mode

  def encode_numeric(text) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.flat_map(fn group ->
      value = group |> Enum.join() |> String.to_integer()

      case length(group) do
        3 -> push_bits(value, 10)
        2 -> push_bits(value, 7)
        1 -> push_bits(value, 4)
      end
    end)
  end

  def encode_alphanumeric(text) do
    chars = Tables.alphanumeric_chars()
    index_map = chars |> Enum.with_index() |> Map.new(fn {c, i} -> {c, i} end)

    text
    |> to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [a, b] ->
        push_bits(Map.fetch!(index_map, a) * 45 + Map.fetch!(index_map, b), 11)

      [a] ->
        push_bits(Map.fetch!(index_map, a), 6)
    end)
  end

  def encode_byte(text) do
    text
    |> :binary.bin_to_list()
    |> Enum.flat_map(&push_bits(&1, 8))
  end

  def push_bits(value, count) do
    for i <- (count - 1)..0//-1, do: value >>> i &&& 1
  end

  defp numeric?(text), do: text =~ ~r/\A[0-9]+\z/

  defp alphanumeric?(text) do
    chars = Tables.alphanumeric_chars()
    text |> to_charlist() |> Enum.all?(&(&1 in chars))
  end
end
