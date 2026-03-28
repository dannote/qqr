defmodule QQR.DataDecoder do
  @moduledoc """
  Decodes the data payload from QR codewords.

  Dispatches on the 4-bit mode indicator (numeric, alphanumeric, byte,
  kanji, ECI) and parses each segment from the bitstream. Segments are
  concatenated into a single text + byte result.
  """

  alias QQR.BitStream

  @alphanumeric_chars List.to_tuple(~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")
  @alphanumeric_count tuple_size(@alphanumeric_chars)

  @kanji_first_range_start 0x8140
  @kanji_first_range_end 0x9FFC
  @kanji_second_range_start 0xC140

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
        {text_io, bytes_rev} =
          Enum.reduce(chunks, {[], []}, fn chunk, {t, b} ->
            {[t, chunk.text], [chunk.bytes | b]}
          end)

        text = IO.iodata_to_binary(text_io)
        bytes = bytes_rev |> Enum.reverse() |> List.flatten()

        {:ok, %QQR.Result{text: text, bytes: bytes, chunks: chunks, version: version}}

      {:error, _} = err ->
        err
    end
  end

  defp decode_loop(stream, size_class, chunks) do
    if BitStream.available(stream) < 4 do
      {:ok, Enum.reverse(chunks)}
    else
      with {:ok, mode, stream} <- BitStream.read_bits(stream, 4) do
        decode_mode(mode, stream, size_class, chunks)
      end
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

  # -- Numeric --

  defp decode_numeric(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.numeric, size_class)

    with {:ok, count, stream} <- BitStream.read_bits(stream, count_bits),
         {:ok, text_io, bytes, stream} <- decode_numeric_digits(stream, count, [], []) do
      text = IO.iodata_to_binary(text_io)
      {:ok, %QQR.Chunk{mode: :numeric, text: text, bytes: bytes}, stream}
    end
  end

  defp decode_numeric_digits(stream, remaining, text_acc, bytes_acc) when remaining >= 3 do
    with {:ok, triple, stream} <- BitStream.read_bits(stream, 10) do
      d1 = div(triple, 100)
      d2 = div(rem(triple, 100), 10)
      d3 = rem(triple, 10)

      if d1 > 9 or d2 > 9 or d3 > 9 do
        {:error, "Invalid numeric triplet: #{triple}"}
      else
        decode_numeric_digits(
          stream,
          remaining - 3,
          [text_acc, Integer.to_string(d1), Integer.to_string(d2), Integer.to_string(d3)],
          [bytes_acc, ?0 + d1, ?0 + d2, ?0 + d3]
        )
      end
    end
  end

  defp decode_numeric_digits(stream, 2, text_acc, bytes_acc) do
    with {:ok, pair, stream} <- BitStream.read_bits(stream, 7) do
      d1 = div(pair, 10)
      d2 = rem(pair, 10)

      if d1 > 9 or d2 > 9 do
        {:error, "Invalid numeric pair: #{pair}"}
      else
        {:ok, [text_acc, Integer.to_string(d1), Integer.to_string(d2)],
         List.flatten([bytes_acc, ?0 + d1, ?0 + d2]), stream}
      end
    end
  end

  defp decode_numeric_digits(stream, 1, text_acc, bytes_acc) do
    with {:ok, digit, stream} <- BitStream.read_bits(stream, 4) do
      if digit > 9 do
        {:error, "Invalid numeric digit: #{digit}"}
      else
        {:ok, [text_acc, Integer.to_string(digit)], List.flatten([bytes_acc, ?0 + digit]), stream}
      end
    end
  end

  defp decode_numeric_digits(stream, 0, text_acc, bytes_acc),
    do: {:ok, text_acc, List.flatten(bytes_acc), stream}

  # -- Alphanumeric --

  defp decode_alphanumeric(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.alphanumeric, size_class)

    with {:ok, count, stream} <- BitStream.read_bits(stream, count_bits),
         {:ok, text_io, bytes, stream} <- decode_alphanumeric_chars(stream, count, [], []) do
      text = IO.iodata_to_binary(text_io)
      {:ok, %QQR.Chunk{mode: :alphanumeric, text: text, bytes: bytes}, stream}
    end
  end

  defp decode_alphanumeric_chars(stream, remaining, text_acc, bytes_acc) when remaining >= 2 do
    with {:ok, pair, stream} <- BitStream.read_bits(stream, 11) do
      c1 = div(pair, 45)
      c2 = rem(pair, 45)

      if c1 >= @alphanumeric_count or c2 >= @alphanumeric_count do
        {:error, "Invalid alphanumeric pair: #{pair}"}
      else
        ch1 = elem(@alphanumeric_chars, c1)
        ch2 = elem(@alphanumeric_chars, c2)

        decode_alphanumeric_chars(
          stream,
          remaining - 2,
          [text_acc, ch1, ch2],
          [bytes_acc, ch1, ch2]
        )
      end
    end
  end

  defp decode_alphanumeric_chars(stream, 1, text_acc, bytes_acc) do
    with {:ok, val, stream} <- BitStream.read_bits(stream, 6) do
      if val >= @alphanumeric_count do
        {:error, "Invalid alphanumeric value: #{val}"}
      else
        ch = elem(@alphanumeric_chars, val)
        {:ok, [text_acc, ch], List.flatten([bytes_acc, ch]), stream}
      end
    end
  end

  defp decode_alphanumeric_chars(stream, 0, text_acc, bytes_acc),
    do: {:ok, text_acc, List.flatten(bytes_acc), stream}

  # -- Byte --

  defp decode_byte(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.byte, size_class)

    with {:ok, count, stream} <- BitStream.read_bits(stream, count_bits),
         {:ok, bytes, stream} <- read_byte_sequence(stream, count, []) do
      text = :erlang.list_to_binary(bytes)
      {:ok, %QQR.Chunk{mode: :byte, text: text, bytes: bytes}, stream}
    end
  end

  defp read_byte_sequence(stream, 0, acc), do: {:ok, Enum.reverse(acc), stream}

  defp read_byte_sequence(stream, remaining, acc) do
    with {:ok, byte, stream} <- BitStream.read_bits(stream, 8) do
      read_byte_sequence(stream, remaining - 1, [byte | acc])
    end
  end

  # -- Kanji --

  defp decode_kanji(stream, size_class) do
    count_bits = Enum.at(@count_bit_sizes.kanji, size_class)

    with {:ok, count, stream} <- BitStream.read_bits(stream, count_bits),
         {:ok, bytes, stream} <- read_kanji_sequence(stream, count, []) do
      {:ok, %QQR.Chunk{mode: :kanji, text: "", bytes: bytes}, stream}
    end
  end

  defp read_kanji_sequence(stream, 0, acc), do: {:ok, Enum.reverse(acc), stream}

  defp read_kanji_sequence(stream, remaining, acc) do
    with {:ok, val, stream} <- BitStream.read_bits(stream, 13) do
      combined =
        if val + @kanji_first_range_start <= @kanji_first_range_end,
          do: val + @kanji_first_range_start,
          else: val + @kanji_second_range_start

      hi = Bitwise.bsr(combined, 8) |> Bitwise.band(0xFF)
      lo = Bitwise.band(combined, 0xFF)
      read_kanji_sequence(stream, remaining - 1, [lo, hi | acc])
    end
  end

  # -- ECI --

  defp decode_eci(stream) do
    with {:ok, first, stream} <- BitStream.read_bits(stream, 8) do
      decode_eci_value(first, stream)
    end
  end

  defp decode_eci_value(first, stream) when Bitwise.band(first, 0x80) == 0,
    do: {:ok, stream}

  defp decode_eci_value(first, stream) when Bitwise.band(first, 0xC0) == 0x80 do
    with {:ok, _second, stream} <- BitStream.read_bits(stream, 8) do
      {:ok, stream}
    end
  end

  defp decode_eci_value(first, stream) when Bitwise.band(first, 0xE0) == 0xC0 do
    with {:ok, _second, stream} <- BitStream.read_bits(stream, 8),
         {:ok, _third, stream} <- BitStream.read_bits(stream, 8) do
      {:ok, stream}
    end
  end

  defp decode_eci_value(_first, _stream), do: {:error, "Invalid ECI assignment"}
end
