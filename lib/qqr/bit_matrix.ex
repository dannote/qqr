defmodule QQR.BitMatrix do
  @moduledoc false

  defstruct [:width, :height, :data]

  @type t :: %__MODULE__{
          width: non_neg_integer(),
          height: non_neg_integer(),
          data: tuple()
        }

  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(width, height) do
    %__MODULE__{width: width, height: height, data: :erlang.make_tuple(width * height, 0)}
  end

  @spec from_list(non_neg_integer(), non_neg_integer(), [0 | 1]) :: t()
  def from_list(width, height, list) when length(list) == width * height do
    %__MODULE__{width: width, height: height, data: List.to_tuple(list)}
  end

  @spec get(t(), integer(), integer()) :: boolean()
  def get(%__MODULE__{width: w, height: h, data: data}, x, y)
      when x >= 0 and x < w and y >= 0 and y < h do
    :erlang.element(y * w + x + 1, data) == 1
  end

  def get(%__MODULE__{}, _x, _y), do: false

  @spec set(t(), non_neg_integer(), non_neg_integer(), boolean()) :: t()
  def set(%__MODULE__{width: w, data: data} = m, x, y, value) do
    %{m | data: :erlang.setelement(y * w + x + 1, data, if(value, do: 1, else: 0))}
  end

  @spec set_region(
          t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          boolean()
        ) :: t()
  def set_region(%__MODULE__{} = matrix, _left, _top, 0, _height, _value), do: matrix
  def set_region(%__MODULE__{} = matrix, _left, _top, _width, 0, _value), do: matrix

  def set_region(%__MODULE__{} = matrix, left, top, width, height, value) do
    Enum.reduce(top..(top + height - 1)//1, matrix, fn y, acc ->
      Enum.reduce(left..(left + width - 1)//1, acc, fn x, acc2 ->
        set(acc2, x, y, value)
      end)
    end)
  end
end
