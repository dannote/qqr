defmodule QQR.Encoder.RS do
  @moduledoc false

  import Bitwise

  alias QQR.GaloisField, as: GF
  alias QQR.GFPoly

  def generate_ec_codewords(data_bytes, ec_count) do
    generator = build_generator(ec_count)
    gen_degree = length(generator) - 1
    padded = data_bytes ++ List.duplicate(0, gen_degree)

    remainder =
      Enum.reduce(data_bytes, padded, fn _byte, message ->
        lead = hd(message)
        rest = tl(message)

        if lead == 0, do: rest, else: divide_step(rest, generator, lead)
      end)

    Enum.take(remainder, gen_degree)
  end

  defp divide_step(rest, generator, lead) do
    generator
    |> Enum.drop(1)
    |> Enum.with_index()
    |> Enum.reduce(rest, fn {g, i}, acc ->
      List.update_at(acc, i, &bxor(&1, GF.multiply(g, lead)))
    end)
  end

  def add_error_correction(data_bytes, ec_info) do
    blocks = split_into_blocks(data_bytes, ec_info)

    ec_blocks =
      Enum.map(blocks, fn block ->
        generate_ec_codewords(block, ec_info.ec_codewords_per_block)
      end)

    interleave(blocks) ++ interleave(ec_blocks)
  end

  defp build_generator(ec_count) do
    Enum.reduce(0..(ec_count - 1), [1], fn i, gen ->
      GFPoly.multiply(gen, [1, GF.exp(i)])
    end)
  end

  defp split_into_blocks(data_bytes, ec_info) do
    {g1, rest} = take_blocks(data_bytes, ec_info.group1_blocks, ec_info.group1_data_cw)
    {g2, _rest} = take_blocks(rest, ec_info.group2_blocks, ec_info.group2_data_cw)
    g1 ++ g2
  end

  defp take_blocks(data, 0, _block_size), do: {[], data}

  defp take_blocks(data, count, block_size) do
    Enum.reduce(1..count, {[], data}, fn _, {blocks, remaining} ->
      {block, rest} = Enum.split(remaining, block_size)
      {blocks ++ [block], rest}
    end)
  end

  defp interleave(blocks) when blocks == [], do: []

  defp interleave(blocks) do
    max_len = blocks |> Enum.map(&length/1) |> Enum.max()

    for i <- 0..(max_len - 1), block <- blocks, i < length(block) do
      Enum.at(block, i)
    end
  end
end
