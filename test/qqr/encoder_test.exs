defmodule QQR.EncoderTest do
  use ExUnit.Case, async: true

  describe "encode/2 roundtrip" do
    test "byte mode (default)" do
      {:ok, matrix} = QQR.encode("Hello World")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "Hello World"
    end

    test "numeric mode" do
      {:ok, matrix} = QQR.encode("1234567890", mode: :numeric)
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "1234567890"
    end

    test "alphanumeric mode" do
      {:ok, matrix} = QQR.encode("HELLO WORLD", mode: :alphanumeric)
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "HELLO WORLD"
    end

    test "auto-detects numeric mode" do
      {:ok, matrix} = QQR.encode("12345")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "12345"
    end

    test "auto-detects alphanumeric mode" do
      {:ok, matrix} = QQR.encode("HELLO")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "HELLO"
    end

    test "single character" do
      {:ok, matrix} = QQR.encode("A")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "A"
    end

    test "UTF-8 text" do
      {:ok, matrix} = QQR.encode("Привет мир")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "Привет мир"
    end

    test "emoji" do
      {:ok, matrix} = QQR.encode("Hello 🌍")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "Hello 🌍"
    end

    test "URL" do
      {:ok, matrix} = QQR.encode("https://elixir-lang.org/getting-started/introduction.html")
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "https://elixir-lang.org/getting-started/introduction.html"
    end

    test "JSON payload" do
      text = ~s({"id":42,"name":"test"})
      {:ok, matrix} = QQR.encode(text)
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == text
    end

    test "WiFi config" do
      text = "WIFI:T:WPA;S:MyNetwork;P:MyPassword;;"
      {:ok, matrix} = QQR.encode(text)
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == text
    end
  end

  describe "EC levels" do
    for ec <- [:low, :medium, :quartile, :high] do
      test "roundtrips with #{ec} EC" do
        {:ok, matrix} = QQR.encode("Test EC", ec_level: unquote(ec))
        {:ok, result} = QQR.decode_matrix(matrix)
        assert result.text == "Test EC"
      end
    end
  end

  describe "version selection" do
    test "auto-selects smallest version" do
      {:ok, matrix} = QQR.encode("Hi")
      assert matrix.width == 21
    end

    test "explicit version" do
      {:ok, matrix} = QQR.encode("Hi", version: 5)
      assert matrix.width == 37
    end

    test "higher versions for longer text" do
      text = String.duplicate("A", 500)
      {:ok, matrix} = QQR.encode(text, ec_level: :low)
      assert matrix.width > 21
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == text
    end

    test "version 10+" do
      text = String.duplicate("Hello ", 50)
      {:ok, matrix} = QQR.encode(text)
      assert matrix.width >= 57
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == text
    end

    test "version 20+" do
      text = String.duplicate("ABCDEFGHIJ", 100)
      {:ok, matrix} = QQR.encode(text)
      assert matrix.width >= 97
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == text
    end

    test "returns error for text too long" do
      text = String.duplicate("A", 5000)
      assert {:error, _} = QQR.encode(text)
    end
  end

  describe "mask selection" do
    test "explicit mask" do
      {:ok, matrix} = QQR.encode("Test", mask: 3)
      {:ok, result} = QQR.decode_matrix(matrix)
      assert result.text == "Test"
    end

    test "all masks produce decodable output" do
      for mask <- 0..7 do
        {:ok, matrix} = QQR.encode("Mask #{mask}", mask: mask)
        {:ok, result} = QQR.decode_matrix(matrix)
        assert result.text == "Mask #{mask}", "Failed with mask #{mask}"
      end
    end
  end

  describe "matrix properties" do
    test "matrix is square" do
      {:ok, matrix} = QQR.encode("Test")
      assert matrix.width == matrix.height
    end

    test "dimension matches version formula" do
      {:ok, matrix} = QQR.encode("Test", version: 3)
      assert matrix.width == 3 * 4 + 17
    end
  end

  describe "cross-validation with qr_code library" do
    test "QQR encoder output is decodable by QQR decoder" do
      for text <- ["Hello", "12345", "HELLO WORLD", "https://example.com"] do
        {:ok, matrix} = QQR.encode(text)
        assert {:ok, result} = QQR.decode_matrix(matrix), "Failed to decode: #{text}"
        assert result.text == text
      end
    end

    test "qr_code encoder output is decodable by QQR decoder" do
      for text <- ["Hello", "12345", "HELLO WORLD", "https://example.com"] do
        {:ok, qr} = QRCode.create(text, :medium)

        matrix =
          qr.matrix
          |> List.flatten()
          |> then(&QQR.BitMatrix.from_list(length(qr.matrix), length(qr.matrix), &1))

        assert {:ok, result} = QQR.decode_matrix(matrix),
               "Failed to decode qr_code output: #{text}"

        assert result.text == text
      end
    end
  end

  describe "consistency" do
    test "50 random strings roundtrip" do
      for i <- 1..50 do
        len = :rand.uniform(100) + 1
        text = for(_ <- 1..len, do: :rand.uniform(94) + 32) |> List.to_string()

        case QQR.encode(text) do
          {:ok, matrix} ->
            assert {:ok, result} = QQR.decode_matrix(matrix),
                   "Failed to decode string ##{i}: #{inspect(text)}"

            assert result.text == text,
                   "Mismatch ##{i}: expected #{inspect(text)}, got #{inspect(result.text)}"

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
