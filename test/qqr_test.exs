defmodule QQRTest do
  use ExUnit.Case

  test "decode_matrix returns error for nil" do
    assert :error = QQR.decode_matrix(nil)
  end
end
