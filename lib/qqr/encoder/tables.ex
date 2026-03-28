defmodule QQR.Encoder.Tables do
  @moduledoc false

  @ec_level_indices %{low: 0, medium: 1, quartile: 2, high: 3}

  @char_count_bits %{
    numeric: {10, 12, 14},
    alphanumeric: {9, 11, 13},
    byte: {8, 16, 16},
    kanji: {8, 10, 12}
  }

  @alphanumeric_chars ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

  def get_ec_info(version, ec_level) do
    v = QQR.Version.get(version)
    index = Map.fetch!(@ec_level_indices, ec_level)

    %QQR.Version.ECLevel{ec_codewords_per_block: ec_per_block, ec_blocks: blocks} =
      Enum.at(v.error_correction_levels, index)

    {g1_blocks, g1_data_cw} = hd(blocks)

    {g2_blocks, g2_data_cw} =
      case blocks do
        [_] -> {0, 0}
        [_, second] -> second
      end

    total_data = g1_blocks * g1_data_cw + g2_blocks * g2_data_cw

    %{
      total_data_codewords: total_data,
      ec_codewords_per_block: ec_per_block,
      group1_blocks: g1_blocks,
      group1_data_cw: g1_data_cw,
      group2_blocks: g2_blocks,
      group2_data_cw: g2_data_cw
    }
  end

  def get_char_count_bits(version, mode) do
    size_class =
      cond do
        version <= 9 -> 0
        version <= 26 -> 1
        true -> 2
      end

    @char_count_bits |> Map.fetch!(mode) |> elem(size_class)
  end

  def alphanumeric_value(char) do
    case :binary.match(<<char>>, List.to_string(@alphanumeric_chars)) do
      {pos, _} -> pos
      :nomatch -> nil
    end
  end

  def alphanumeric_chars, do: @alphanumeric_chars
end
