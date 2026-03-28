defmodule QQR.Encoder do
  @moduledoc false

  alias QQR.Encoder.{Data, Mask, Matrix}

  def encode(text, opts \\ []) do
    with {:ok, %{version: version, ec_level: ec_level, bits: bits}} <-
           Data.encode_data(text, opts) do
      size = QQR.Version.dimension(version)
      requested_mask = Keyword.get(opts, :mask)

      matrix_map = Matrix.build(version, bits)

      {_mask, final_matrix} =
        Mask.select_best_mask(matrix_map, size, version, ec_level, requested_mask)

      bit_matrix = Matrix.to_bit_matrix(final_matrix, size)

      {:ok, bit_matrix}
    end
  end
end
