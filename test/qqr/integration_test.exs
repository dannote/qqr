defmodule QQR.IntegrationTest do
  use ExUnit.Case, async: true

  alias QQR.BitMatrix

  defp qr_to_bit_matrix(%QRCode.QR{matrix: matrix}) do
    height = length(matrix)
    width = length(hd(matrix))
    flat = List.flatten(matrix)
    BitMatrix.from_list(width, height, flat)
  end

  describe "decode_matrix/1 with qr_code-generated matrices" do
    test "decodes numeric content" do
      {:ok, qr} = QRCode.create("01234567", :medium)
      matrix = qr_to_bit_matrix(qr)
      assert {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "01234567"
      assert result.version == qr.version
    end

    test "decodes short alphanumeric content" do
      {:ok, qr} = QRCode.create("HELLO", :medium)
      matrix = qr_to_bit_matrix(qr)
      assert {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "HELLO"
    end

    test "decodes byte-mode content" do
      {:ok, qr} = QRCode.create("Hello World", :medium)
      matrix = qr_to_bit_matrix(qr)
      assert {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "Hello World"
    end

    test "decodes longer text requiring higher version" do
      text = "https://elixir-lang.org/getting-started/introduction.html"
      {:ok, qr} = QRCode.create(text, :low)
      matrix = qr_to_bit_matrix(qr)
      assert {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == text
    end

    test "decodes with high error correction" do
      {:ok, qr} = QRCode.create("QQR", :high)
      matrix = qr_to_bit_matrix(qr)
      assert {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "QQR"
    end

    test "returns error for empty matrix" do
      matrix = BitMatrix.new(21, 21)
      assert :error = QQR.decode_matrix(matrix)
    end
  end
end
