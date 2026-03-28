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

  @alignment_positions %{
    1 => [],
    2 => [6, 18],
    3 => [6, 22],
    4 => [6, 26],
    5 => [6, 30],
    6 => [6, 34],
    7 => [6, 22, 38],
    8 => [6, 24, 42],
    9 => [6, 26, 46],
    10 => [6, 28, 50],
    11 => [6, 30, 54],
    12 => [6, 32, 58],
    13 => [6, 34, 62],
    14 => [6, 26, 46, 66],
    15 => [6, 26, 48, 70],
    16 => [6, 26, 50, 74],
    17 => [6, 30, 54, 78],
    18 => [6, 30, 56, 82],
    19 => [6, 30, 58, 86],
    20 => [6, 34, 62, 90],
    21 => [6, 28, 50, 72, 94],
    22 => [6, 26, 50, 74, 98],
    23 => [6, 30, 54, 74, 102],
    24 => [6, 28, 54, 80, 106],
    25 => [6, 32, 58, 84, 110],
    26 => [6, 30, 58, 86, 114],
    27 => [6, 34, 62, 90, 118],
    28 => [6, 26, 50, 74, 98, 122],
    29 => [6, 30, 54, 78, 102, 126],
    30 => [6, 26, 52, 78, 104, 130],
    31 => [6, 30, 56, 82, 108, 134],
    32 => [6, 34, 60, 86, 112, 138],
    33 => [6, 30, 58, 86, 114, 142],
    34 => [6, 34, 62, 90, 118, 146],
    35 => [6, 30, 54, 78, 102, 126, 150],
    36 => [6, 24, 50, 76, 102, 128, 154],
    37 => [6, 28, 54, 80, 106, 132, 158],
    38 => [6, 32, 58, 84, 110, 136, 162],
    39 => [6, 26, 54, 82, 110, 138, 166],
    40 => [6, 30, 58, 86, 114, 142, 170]
  }

  @version_info %{
    7 => 0x07C94,
    8 => 0x085BC,
    9 => 0x09A99,
    10 => 0x0A4D3,
    11 => 0x0BBF6,
    12 => 0x0C762,
    13 => 0x0D847,
    14 => 0x0E60D,
    15 => 0x0F928,
    16 => 0x10B78,
    17 => 0x1145D,
    18 => 0x12A17,
    19 => 0x13532,
    20 => 0x149A6,
    21 => 0x15683,
    22 => 0x168C9,
    23 => 0x177EC,
    24 => 0x18EC4,
    25 => 0x191E1,
    26 => 0x1AFAB,
    27 => 0x1B08E,
    28 => 0x1CC1A,
    29 => 0x1D33F,
    30 => 0x1ED75,
    31 => 0x1F250,
    32 => 0x209D5,
    33 => 0x216F0,
    34 => 0x228BA,
    35 => 0x2379F,
    36 => 0x24B0B,
    37 => 0x2542E,
    38 => 0x26A64,
    39 => 0x27541,
    40 => 0x28C69
  }

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
  def alignment_positions(version), do: Map.fetch!(@alignment_positions, version)
  def version_info(version) when version >= 7, do: Map.fetch!(@version_info, version)
  def version_info(_version), do: nil
end
