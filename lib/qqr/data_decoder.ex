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
        {text_iodata, bytes_reversed} =
          Enum.reduce(chunks, {[], []}, fn chunk, {text_acc, bytes_acc} ->
            {[text_acc, chunk.text], [chunk.bytes | bytes_acc]}
          end)

        text = IO.iodata_to_binary(text_iodata)
        bytes = bytes_reversed |> Enum.reverse() |> List.flatten()

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
      decode_mode(mode, stream, size_class, chunks)
    end
  end

  defp decode_mode(0x0, _stream, _size_class, chunks), do: {:ok, Enum.reverse(chunks)}

  defp decode_mode(0x1, stream, size_class, chunks) do
    with {:ok, chunk, stream} <- decode_numeric(stream, size_class) do
      decode_loop(stream, size_class, [chunk | chunks])
    end
  end

  defp decode_mode(0x2, stream, size_class, chunks) do
    with {:ok, chunk, stream} <- decode_alphanumeric(stream, size_class) do
      decode_loop(stream, size_class, [chunk | chunks])
    end
  end

  defp decode_mode(0x4, stream, size_class, chunks) do
    with {:ok, chunk, stream} <- decode_byte(stream, size_class) do
      decode_loop(stream, size_class, [chunk | chunks])
    end
  end

  defp decode_mode(0x7, stream, size_class, chunks) do
    with {:ok, stream} <- decode_eci(stream) do
      decode_loop(stream, size_class, chunks)
    end
  end

  defp decode_mode(0x8, stream, size_class, chunks) do
    with {:ok, chunk, stream} <- decode_kanji(stream, size_class) do
      decode_loop(stream, size_class, [chunk | chunks])
    end
  end

  defp decode_mode(mode, _stream, _size_class, _chunks),
    do: {:error, "Unknown mode: #{mode}"}

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
    new_bytes = [?0 + d3, ?0 + d2, ?0 + d1]
    decode_numeric_digits(stream, remaining - 3, text <> chars, new_bytes ++ bytes)
  end

  defp decode_numeric_digits(stream, 2, text, bytes) do
    {pair, stream} = BitStream.read_bits(stream, 7)
    d1 = div(pair, 10)
    d2 = rem(pair, 10)

    if d1 > 9 or d2 > 9 do
      raise "Invalid numeric pair: #{pair}"
    end

    chars = Integer.to_string(d1) <> Integer.to_string(d2)
    {text <> chars, [?0 + d2, ?0 + d1 | bytes], stream}
  end

  defp decode_numeric_digits(stream, 1, text, bytes) do
    {digit, stream} = BitStream.read_bits(stream, 4)

    if digit > 9 do
      raise "Invalid numeric digit: #{digit}"
    end

    {text <> Integer.to_string(digit), [?0 + digit | bytes], stream}
  end

  defp decode_numeric_digits(stream, 0, text, bytes), do: {text, Enum.reverse(bytes), stream}

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
    decode_alphanumeric_chars(stream, remaining - 2, text <> <<ch1, ch2>>, [ch2, ch1 | bytes])
  end

  defp decode_alphanumeric_chars(stream, 1, text, bytes) do
    {val, stream} = BitStream.read_bits(stream, 6)

    if val >= length(@alphanumeric_chars) do
      raise "Invalid alphanumeric value: #{val}"
    end

    ch = Enum.at(@alphanumeric_chars, val)
    {text <> <<ch>>, [ch | bytes], stream}
  end

  defp decode_alphanumeric_chars(stream, 0, text, bytes), do: {text, Enum.reverse(bytes), stream}

  defp decode_byte(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.byte, size_class)
    {count, stream} = BitStream.read_bits(stream, count_bits)

    {bytes_reversed, stream} =
      Enum.reduce(1..count//1, {[], stream}, fn _, {acc, s} ->
        {byte, s} = BitStream.read_bits(s, 8)
        {[byte | acc], s}
      end)

    bytes = Enum.reverse(bytes_reversed)
    text = :erlang.list_to_binary(bytes)
    {:ok, %{mode: :byte, text: text, bytes: bytes}, stream}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp decode_kanji(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.kanji, size_class)
    {count, stream} = BitStream.read_bits(stream, count_bits)

    {bytes_reversed, stream} =
      Enum.reduce(1..count//1, {[], stream}, fn _, {acc, s} ->
        {val, s} = BitStream.read_bits(s, 13)

        combined = if val + 0x8140 <= 0x9FFC, do: val + 0x8140, else: val + 0xC140

        hi = Bitwise.bsr(combined, 8) |> Bitwise.band(0xFF)
        lo = Bitwise.band(combined, 0xFF)
        {[lo, hi | acc], s}
      end)

    bytes = Enum.reverse(bytes_reversed)
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
