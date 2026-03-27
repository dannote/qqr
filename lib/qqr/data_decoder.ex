defmodule QQR.DataDecoder do
  @moduledoc false

  alias QQR.BitStream

  @alphanumeric_chars ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

  @count_bit_sizes %{
    numeric: [10, 12, 14],
    alphanumeric: [9, 11, 13],
    byte: [8, 16, 16],
    kanji: [8, 10, 12]
  }

  def decode(data, version) when is_list(data) do
    stream = BitStream.new(data)

    size_class =
      cond do
        version <= 9 -> 0
        version <= 26 -> 1
        true -> 2
      end

    case decode_loop(stream, size_class, []) do
      {:ok, chunks} ->
        {text, bytes} =
          Enum.reduce(chunks, {"", []}, fn chunk, {text, bytes} ->
            {text <> chunk.text, bytes ++ chunk.bytes}
          end)

        {:ok, %{text: text, bytes: bytes, chunks: chunks, version: version}}

      {:error, _} = err ->
        err
    end
  end

  defp decode_loop(stream, size_class, chunks) do
    if BitStream.available(stream) < 4 do
      {:ok, Enum.reverse(chunks)}
    else
      {mode, stream} = BitStream.read_bits(stream, 4)

      case mode do
        0x0 ->
          {:ok, Enum.reverse(chunks)}

        0x1 ->
          with {:ok, chunk, stream} <- decode_numeric(stream, size_class) do
            decode_loop(stream, size_class, [chunk | chunks])
          end

        0x2 ->
          with {:ok, chunk, stream} <- decode_alphanumeric(stream, size_class) do
            decode_loop(stream, size_class, [chunk | chunks])
          end

        0x4 ->
          with {:ok, chunk, stream} <- decode_byte(stream, size_class) do
            decode_loop(stream, size_class, [chunk | chunks])
          end

        0x7 ->
          with {:ok, stream} <- decode_eci(stream) do
            decode_loop(stream, size_class, chunks)
          end

        0x8 ->
          with {:ok, chunk, stream} <- decode_kanji(stream, size_class) do
            decode_loop(stream, size_class, [chunk | chunks])
          end

        _ ->
          {:error, "Unknown mode: #{mode}"}
      end
    end
  end

  defp decode_numeric(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.numeric, size_class)
    {count, stream} = BitStream.read_bits(stream, count_bits)

    {text, bytes, stream} = decode_numeric_digits(stream, count, "", [])
    {:ok, %{mode: :numeric, text: text, bytes: bytes}, stream}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp decode_numeric_digits(stream, remaining, text, bytes) when remaining >= 3 do
    {triple, stream} = BitStream.read_bits(stream, 10)
    d1 = div(triple, 100)
    d2 = div(rem(triple, 100), 10)
    d3 = rem(triple, 10)

    if d1 > 9 or d2 > 9 or d3 > 9 do
      raise "Invalid numeric triplet: #{triple}"
    end

    chars = Integer.to_string(d1) <> Integer.to_string(d2) <> Integer.to_string(d3)
    new_bytes = [?0 + d1, ?0 + d2, ?0 + d3]
    decode_numeric_digits(stream, remaining - 3, text <> chars, bytes ++ new_bytes)
  end

  defp decode_numeric_digits(stream, 2, text, bytes) do
    {pair, stream} = BitStream.read_bits(stream, 7)
    d1 = div(pair, 10)
    d2 = rem(pair, 10)

    if d1 > 9 or d2 > 9 do
      raise "Invalid numeric pair: #{pair}"
    end

    chars = Integer.to_string(d1) <> Integer.to_string(d2)
    {text <> chars, bytes ++ [?0 + d1, ?0 + d2], stream}
  end

  defp decode_numeric_digits(stream, 1, text, bytes) do
    {digit, stream} = BitStream.read_bits(stream, 4)

    if digit > 9 do
      raise "Invalid numeric digit: #{digit}"
    end

    {text <> Integer.to_string(digit), bytes ++ [?0 + digit], stream}
  end

  defp decode_numeric_digits(stream, 0, text, bytes), do: {text, bytes, stream}

  defp decode_alphanumeric(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.alphanumeric, size_class)
    {count, stream} = BitStream.read_bits(stream, count_bits)

    {text, bytes, stream} = decode_alphanumeric_chars(stream, count, "", [])
    {:ok, %{mode: :alphanumeric, text: text, bytes: bytes}, stream}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp decode_alphanumeric_chars(stream, remaining, text, bytes) when remaining >= 2 do
    {pair, stream} = BitStream.read_bits(stream, 11)
    c1 = div(pair, 45)
    c2 = rem(pair, 45)

    if c1 >= length(@alphanumeric_chars) or c2 >= length(@alphanumeric_chars) do
      raise "Invalid alphanumeric pair: #{pair}"
    end

    ch1 = Enum.at(@alphanumeric_chars, c1)
    ch2 = Enum.at(@alphanumeric_chars, c2)
    decode_alphanumeric_chars(stream, remaining - 2, text <> <<ch1, ch2>>, bytes ++ [ch1, ch2])
  end

  defp decode_alphanumeric_chars(stream, 1, text, bytes) do
    {val, stream} = BitStream.read_bits(stream, 6)

    if val >= length(@alphanumeric_chars) do
      raise "Invalid alphanumeric value: #{val}"
    end

    ch = Enum.at(@alphanumeric_chars, val)
    {text <> <<ch>>, bytes ++ [ch], stream}
  end

  defp decode_alphanumeric_chars(stream, 0, text, bytes), do: {text, bytes, stream}

  defp decode_byte(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.byte, size_class)
    {count, stream} = BitStream.read_bits(stream, count_bits)

    {bytes, stream} =
      Enum.reduce(1..count//1, {[], stream}, fn _, {acc, s} ->
        {byte, s} = BitStream.read_bits(s, 8)
        {acc ++ [byte], s}
      end)

    text = :erlang.list_to_binary(bytes)
    {:ok, %{mode: :byte, text: text, bytes: bytes}, stream}
  rescue
    e -> {:error, Exception.message(e)}
  end

  # TODO: Shift-JIS text conversion
  defp decode_kanji(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.kanji, size_class)
    {count, stream} = BitStream.read_bits(stream, count_bits)

    {bytes, stream} =
      Enum.reduce(1..count//1, {[], stream}, fn _, {acc, s} ->
        {val, s} = BitStream.read_bits(s, 13)

        combined =
          cond do
            val + 0x8140 <= 0x9FFC -> val + 0x8140
            true -> val + 0xC140
          end

        hi = Bitwise.bsr(combined, 8) |> Bitwise.band(0xFF)
        lo = Bitwise.band(combined, 0xFF)
        {acc ++ [hi, lo], s}
      end)

    {:ok, %{mode: :kanji, text: "", bytes: bytes}, stream}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp decode_eci(stream) do
    {first, stream} = BitStream.read_bits(stream, 8)

    cond do
      Bitwise.band(first, 0x80) == 0 ->
        {:ok, stream}

      Bitwise.band(first, 0xC0) == 0x80 ->
        {_second, stream} = BitStream.read_bits(stream, 8)
        {:ok, stream}

      Bitwise.band(first, 0xE0) == 0xC0 ->
        {_second, stream} = BitStream.read_bits(stream, 8)
        {_third, stream} = BitStream.read_bits(stream, 8)
        {:ok, stream}

      true ->
        {:error, "Invalid ECI assignment"}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
