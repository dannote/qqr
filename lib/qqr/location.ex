defmodule QQR.Location do
  @moduledoc "QR code location coordinates in the source image."

  defstruct [
    :top_left_corner,
    :top_right_corner,
    :bottom_left_corner,
    :bottom_right_corner,
    :top_left_finder,
    :top_right_finder,
    :bottom_left_finder,
    :alignment
  ]

  @type point :: {number(), number()}

  @type t :: %__MODULE__{
          top_left_corner: point(),
          top_right_corner: point(),
          bottom_left_corner: point(),
          bottom_right_corner: point(),
          top_left_finder: point(),
          top_right_finder: point(),
          bottom_left_finder: point(),
          alignment: point() | nil
        }
end
