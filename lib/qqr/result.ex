defmodule QQR.Result do
  @moduledoc "Decoded QR code result."

  defstruct [:text, :bytes, :chunks, :version, :location]

  @type t :: %__MODULE__{
          text: String.t(),
          bytes: [non_neg_integer()],
          chunks: [QQR.Chunk.t()],
          version: pos_integer(),
          location: QQR.Location.t() | nil
        }
end
