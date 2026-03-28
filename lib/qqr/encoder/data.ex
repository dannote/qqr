defmodule QQR.Encoder.Data do
  @moduledoc false

  import Bitwise

  alias QQR.Encoder.Mode
  alias QQR.Encoder.RS
  alias QQR.Encoder.Tables

  @mode_indicators %{numeric: 0b0001, alphanumeric: 0b0010, byte: 0b0100}

  def encode_data(text, opts \\ []) do
    ec_level = Keyword.get(opts, :ec_level, :medium)
    requested_mode = Keyword.get(opts, :mode)
    requested_version = Keyword.get(opts, :version)

    mode = Mode.select_mode(text, requested_mode)
    char_count = if mode == :byte, do: byte_size(text), else: String.length(text)

    case select_version(text, mode, ec_level, char_count, requested_version) do
      {:ok, version} ->
        ec_info = Tables.get_ec_info(version, ec_level)
        capacity_bits = ec_info.total_data_codewords * 8

        bits =
          build_data_bits(text, mode, version, char_count)
          |> add_terminator(capacity_bits)
          |> pad_to_byte_boundary()
          |> pad_to_capacity(capacity_bits)

        data_bytes = bits_to_bytes(bits)
        final_bytes = RS.add_error_correction(data_bytes, ec_info)
        final_bits = Enum.flat_map(final_bytes, &Mode.push_bits(&1, 8))

        {:ok, %{version: version, ec_level: ec_level, bits: final_bits}}

      {:error, _} = error ->
        error
    end
  end

  defp build_data_bits(text, mode, version, char_count) do
    mode_bits = Mode.push_bits(Map.fetch!(@mode_indicators, mode), 4)
    count_bit_len = Tables.get_char_count_bits(version, mode)
    count_bits = Mode.push_bits(char_count, count_bit_len)

    payload_bits =
      case mode do
        :numeric -> Mode.encode_numeric(text)
        :alphanumeric -> Mode.encode_alphanumeric(text)
        :byte -> Mode.encode_byte(text)
      end

    mode_bits ++ count_bits ++ payload_bits
  end

  defp select_version(_text, _mode, _ec_level, _char_count, version) when is_integer(version) do
    {:ok, version}
  end

  defp select_version(text, mode, ec_level, char_count, nil) do
    result =
      Enum.find(1..40, fn version ->
        ec_info = Tables.get_ec_info(version, ec_level)
        capacity_bits = ec_info.total_data_codewords * 8
        count_bit_len = Tables.get_char_count_bits(version, mode)

        payload_len =
          case mode do
            :numeric -> Mode.encode_numeric(text) |> length()
            :alphanumeric -> Mode.encode_alphanumeric(text) |> length()
            :byte -> Mode.encode_byte(text) |> length()
          end

        total_bits = 4 + count_bit_len + payload_len

        max_char_count = (1 <<< count_bit_len) - 1
        char_count <= max_char_count and total_bits <= capacity_bits
      end)

    if result, do: {:ok, result}, else: {:error, "data too large for any QR version"}
  end

  defp add_terminator(bits, capacity_bits) do
    remaining = capacity_bits - length(bits)
    terminator_len = min(remaining, 4)
    bits ++ List.duplicate(0, terminator_len)
  end

  defp pad_to_byte_boundary(bits) do
    remainder = rem(length(bits), 8)

    if remainder == 0 do
      bits
    else
      bits ++ List.duplicate(0, 8 - remainder)
    end
  end

  defp pad_to_capacity(bits, capacity_bits) do
    pad_bytes_needed = div(capacity_bits - length(bits), 8)
    pad_pattern = Stream.cycle([0xEC, 0x11]) |> Enum.take(pad_bytes_needed)
    bits ++ Enum.flat_map(pad_pattern, &Mode.push_bits(&1, 8))
  end

  defp bits_to_bytes(bits) do
    bits
    |> Enum.chunk_every(8)
    |> Enum.map(fn byte_bits ->
      Enum.reduce(byte_bits, 0, fn bit, acc -> Bitwise.bsl(acc, 1) + bit end)
    end)
  end
end
