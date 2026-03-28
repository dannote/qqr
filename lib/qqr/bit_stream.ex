defmodule QQR.BitStream do
  @moduledoc false

  defstruct [:data, :bit_offset]

  def new(bytes) when is_list(bytes),
    do: %__MODULE__{data: :erlang.list_to_binary(bytes), bit_offset: 0}

  def new(bytes) when is_binary(bytes), do: %__MODULE__{data: bytes, bit_offset: 0}

  def read_bits(%__MODULE__{data: data, bit_offset: offset} = stream, n)
      when n >= 1 and n <= 32 do
    if available(stream) < n do
      :error
    else
      <<_skip::size(offset), value::size(n), _rest::bits>> = data
      {:ok, value, %{stream | bit_offset: offset + n}}
    end
  end

  def available(%__MODULE__{data: data, bit_offset: offset}), do: bit_size(data) - offset
end
