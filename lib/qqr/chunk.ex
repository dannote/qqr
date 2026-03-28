defmodule QQR.Chunk do
  @moduledoc "A single data segment within a QR code."

  defstruct [:mode, :text, :bytes]

  @type t :: %__MODULE__{
          mode: :numeric | :alphanumeric | :byte | :kanji,
          text: String.t(),
          bytes: [non_neg_integer()]
        }
end
