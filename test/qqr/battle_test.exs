defmodule QQR.BattleTest do
  use ExUnit.Case, async: true

  alias QQR.BitMatrix

  # -- Helpers --

  defp qr_to_bit_matrix(%QRCode.QR{matrix: matrix}) do
    height = length(matrix)
    width = length(hd(matrix))
    BitMatrix.from_list(width, height, List.flatten(matrix))
  end

  defp qr_to_rgba(%QRCode.QR{matrix: matrix}, scale \\ 4, quiet \\ 4) do
    dim = length(matrix)
    img_dim = (dim + quiet * 2) * scale

    quiet_row = :binary.copy(<<255, 255, 255, 255>>, img_dim)
    quiet_px = :binary.copy(<<255, 255, 255, 255>>, quiet * scale)
    top = :binary.copy(quiet_row, quiet * scale)
    data = render_rows(matrix, scale, quiet_px)
    bottom = :binary.copy(quiet_row, quiet * scale)
    {top <> data <> bottom, img_dim}
  end

  defp render_rows(matrix, scale, quiet_px) do
    for row <- matrix, _sy <- 1..scale, into: <<>> do
      rpx = render_cells(row, scale)
      quiet_px <> rpx <> quiet_px
    end
  end

  defp render_cells(row, scale) do
    for cell <- row, _sx <- 1..scale, into: <<>> do
      if cell == 1, do: <<0, 0, 0, 255>>, else: <<255, 255, 255, 255>>
    end
  end

  defp corrupt_matrix(matrix, positions) do
    Enum.reduce(positions, matrix, fn {x, y}, m ->
      BitMatrix.set(m, x, y, not BitMatrix.get(m, x, y))
    end)
  end

  # -- 1. All EC levels × versions via decode_matrix --

  describe "EC levels × versions (decode_matrix)" do
    for {ec, ec_name} <- [{:low, "L"}, {:medium, "M"}, {:quartile, "Q"}, {:high, "H"}],
        {len, expected_min_version} <- [
          {1, 1},
          {10, 1},
          {50, 3},
          {200, 9},
          {500, 15},
          {1000, 22}
        ] do
      @tag timeout: 10_000
      test "#{ec_name} ec, #{len} chars" do
        text = String.duplicate("x", unquote(len))

        case QRCode.create(text, unquote(ec)) do
          {:ok, qr} ->
            matrix = qr_to_bit_matrix(qr)
            assert {:ok, result} = QQR.decode_matrix(matrix)
            assert result.text == text
            assert result.version >= unquote(expected_min_version)

          {:error, _} ->
            :skip
        end
      end
    end
  end

  # -- 2. Full RGBA pipeline × versions --

  describe "full RGBA pipeline" do
    for {len, label} <- [
          {5, "tiny"},
          {20, "small"},
          {100, "medium"},
          {500, "large"},
          {1000, "xlarge"}
        ] do
      @tag timeout: 30_000
      test "decodes #{label} (#{len} chars) from RGBA" do
        text = String.duplicate("B", unquote(len))

        case QRCode.create(text, :medium) do
          {:ok, qr} ->
            {rgba, dim} = qr_to_rgba(qr)
            assert {:ok, result} = QQR.decode(rgba, dim, dim, inversion: :dont_invert)
            assert result.text == text

          {:error, _} ->
            :skip
        end
      end
    end
  end

  # -- 3. Diverse content --

  describe "content diversity (decode_matrix)" do
    test "digits only" do
      {:ok, qr} = QRCode.create("1234567890", :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == "1234567890"
    end

    test "uppercase only" do
      {:ok, qr} = QRCode.create("HELLO WORLD", :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == "HELLO WORLD"
    end

    test "URL" do
      url = "https://elixir-lang.org/getting-started/introduction.html"
      {:ok, qr} = QRCode.create(url, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == url
    end

    test "UTF-8 text" do
      text = "Привет мир"
      {:ok, qr} = QRCode.create(text, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "emoji" do
      text = "Hello 🌍🎉"
      {:ok, qr} = QRCode.create(text, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "JSON payload" do
      text = ~s({"id":42,"name":"test","active":true})
      {:ok, qr} = QRCode.create(text, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "single character" do
      {:ok, qr} = QRCode.create("A", :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == "A"
    end

    test "binary data" do
      text = <<0, 1, 2, 255, 128, 64>>
      {:ok, qr} = QRCode.create(text, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.bytes == [0, 1, 2, 255, 128, 64]
    end

    test "vCard" do
      text = """
      BEGIN:VCARD
      VERSION:3.0
      N:Doe;John
      FN:John Doe
      TEL:+1234567890
      END:VCARD\
      """

      {:ok, qr} = QRCode.create(text, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "WiFi config" do
      text = "WIFI:T:WPA;S:MyNetwork;P:MyPassword;;"
      {:ok, qr} = QRCode.create(text, :medium)
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end
  end

  # -- 4. Error correction stress --

  describe "error correction recovery" do
    test "recovers from light corruption (v1-M)" do
      {:ok, qr} = QRCode.create("Test", :medium)
      matrix = qr_to_bit_matrix(qr)

      # Flip a few data-area pixels (avoid finder patterns)
      corrupted = corrupt_matrix(matrix, [{10, 10}, {11, 10}, {10, 11}])
      assert {:ok, result} = QQR.decode_matrix(corrupted)
      assert result.text == "Test"
    end

    test "recovers from heavier corruption with high EC" do
      {:ok, qr} = QRCode.create("Error test", :high)
      matrix = qr_to_bit_matrix(qr)

      positions = for x <- 10..14, y <- 10..14, do: {x, y}
      corrupted = corrupt_matrix(matrix, positions)
      assert {:ok, result} = QQR.decode_matrix(corrupted)
      assert result.text == "Error test"
    end

    test "fails gracefully on excessive corruption" do
      {:ok, qr} = QRCode.create("Fail", :low)
      matrix = qr_to_bit_matrix(qr)

      positions = for x <- 8..18, y <- 8..18, do: {x, y}
      corrupted = corrupt_matrix(matrix, positions)
      assert :error = QQR.decode_matrix(corrupted)
    end
  end

  # -- 5. Higher versions --

  describe "higher versions (decode_matrix)" do
    test "version 10+" do
      text = String.duplicate("Hello World! ", 20)
      {:ok, qr} = QRCode.create(text, :medium)
      assert qr.version >= 10
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "version 20+" do
      text = String.duplicate("ABCDEFGHIJ", 100)
      {:ok, qr} = QRCode.create(text, :medium)
      assert qr.version >= 20
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "version 30+" do
      text = String.duplicate("0123456789", 200)
      {:ok, qr} = QRCode.create(text, :medium)
      assert qr.version >= 30
      assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
      assert result.text == text
    end

    test "version ~40 (near max capacity)" do
      text = String.duplicate("Z", 2500)

      case QRCode.create(text, :low) do
        {:ok, qr} ->
          assert qr.version >= 36
          assert {:ok, result} = QQR.decode_matrix(qr_to_bit_matrix(qr))
          assert result.text == text

        {:error, _} ->
          :skip
      end
    end
  end

  # -- 6. Mirror decode --

  describe "mirror/transpose" do
    test "decodes transposed matrix" do
      {:ok, qr} = QRCode.create("Mirror", :medium)
      matrix = qr_to_bit_matrix(qr)
      dim = matrix.width

      transposed =
        Enum.reduce(0..(dim - 1), BitMatrix.new(dim, dim), fn x, acc ->
          Enum.reduce(0..(dim - 1), acc, fn y, acc2 ->
            BitMatrix.set(acc2, y, x, BitMatrix.get(matrix, x, y))
          end)
        end)

      assert {:ok, result} = QQR.decode_matrix(transposed)
      assert result.text == "Mirror"
    end
  end

  # -- 7. Full pipeline with inversion --

  describe "inversion modes" do
    test "decodes inverted QR (light on dark)" do
      {:ok, qr} = QRCode.create("Inverted", :medium)
      dim = length(qr.matrix)
      scale = 4
      quiet = 4
      img_dim = (dim + quiet * 2) * scale

      # Build inverted RGBA: black background, white modules
      quiet_row = :binary.copy(<<0, 0, 0, 255>>, img_dim)
      quiet_px = :binary.copy(<<0, 0, 0, 255>>, quiet * scale)
      top = :binary.copy(quiet_row, quiet * scale)

      data =
        for row <- qr.matrix, _sy <- 1..scale, into: <<>> do
          rpx =
            for cell <- row, _sx <- 1..scale, into: <<>> do
              if cell == 1, do: <<255, 255, 255, 255>>, else: <<0, 0, 0, 255>>
            end

          quiet_px <> rpx <> quiet_px
        end

      bottom = :binary.copy(quiet_row, quiet * scale)
      rgba = top <> data <> bottom

      assert {:ok, result} = QQR.decode(rgba, img_dim, img_dim, inversion: :attempt_both)
      assert result.text == "Inverted"
    end
  end

  # -- 8. Consistency: encode then decode multiple times --

  describe "consistency" do
    test "100 random strings roundtrip" do
      for i <- 1..100 do
        len = :rand.uniform(50) + 1
        text = for(_ <- 1..len, do: :rand.uniform(94) + 32) |> List.to_string()

        case QRCode.create(text, :medium) do
          {:ok, qr} ->
            matrix = qr_to_bit_matrix(qr)

            assert {:ok, result} = QQR.decode_matrix(matrix),
                   "Failed to decode string ##{i}: #{inspect(text)} (v#{qr.version})"

            assert result.text == text,
                   "Mismatch on string ##{i}: expected #{inspect(text)}, got #{inspect(result.text)}"

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
