defmodule QQR.DataDecoderTest do
  use ExUnit.Case, async: true

  alias QQR.DataDecoder

  # Builds a QR data payload from a bitstream specification.
  # Each entry is {value, bit_count}. Pads to full bytes.
  defp build_payload(bits_spec) do
    binary =
      Enum.reduce(bits_spec, <<>>, fn {value, count}, acc ->
        <<acc::bits, value::size(count)>>
      end)

    pad_bits = rem(8 - rem(bit_size(binary), 8), 8)
    padded = <<binary::bits, 0::size(pad_bits)>>
    :erlang.binary_to_list(padded)
  end

  describe "numeric mode" do
    test "decodes '1234567890'" do
      # Mode 0x1, count=10 (10 bits for v1-9)
      # 123 -> 10 bits, 456 -> 10 bits, 789 -> 10 bits, 0 -> 4 bits
      payload =
        build_payload([
          {0x1, 4},
          {10, 10},
          {123, 10},
          {456, 10},
          {789, 10},
          {0, 4},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "1234567890"
      assert result.version == 1
      assert hd(result.chunks).mode == :numeric
    end

    test "decodes a two-digit remainder" do
      # "12" -> count=2, pair 12 in 7 bits
      payload =
        build_payload([
          {0x1, 4},
          {2, 10},
          {12, 7},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "12"
    end

    test "decodes a single-digit remainder" do
      # "1" -> count=1, digit 1 in 4 bits
      payload =
        build_payload([
          {0x1, 4},
          {1, 10},
          {1, 4},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "1"
    end
  end

  describe "alphanumeric mode" do
    test "decodes 'HELLO WORLD'" do
      # Mode 0x2, count=11 (9 bits for v1-9)
      # Pairs: HE=17*45+14=779, LL=21*45+21=966, O =24*45+36=1116,
      #        WO=32*45+24=1464, RL=27*45+21=1236, D=13
      payload =
        build_payload([
          {0x2, 4},
          {11, 9},
          {17 * 45 + 14, 11},
          {21 * 45 + 21, 11},
          {24 * 45 + 36, 11},
          {32 * 45 + 24, 11},
          {27 * 45 + 21, 11},
          {13, 6},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "HELLO WORLD"
      assert hd(result.chunks).mode == :alphanumeric
    end

    test "decodes even-length string 'AB'" do
      payload =
        build_payload([
          {0x2, 4},
          {2, 9},
          {10 * 45 + 11, 11},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "AB"
    end
  end

  describe "byte mode" do
    test "decodes 'Hello'" do
      # Mode 0x4, count=5 (8 bits for v1-9), then 5 bytes
      payload =
        build_payload([
          {0x4, 4},
          {5, 8},
          {?H, 8},
          {?e, 8},
          {?l, 8},
          {?l, 8},
          {?o, 8},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "Hello"
      assert result.bytes == ~c"Hello"
      assert hd(result.chunks).mode == :byte
    end

    test "decodes UTF-8 bytes" do
      bytes = :binary.bin_to_list("café")

      spec =
        [{0x4, 4}, {length(bytes), 8}] ++
          Enum.map(bytes, &{&1, 8}) ++
          [{0x0, 4}]

      payload = build_payload(spec)
      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "café"
    end
  end

  describe "mixed modes" do
    test "numeric followed by byte" do
      payload =
        build_payload([
          {0x1, 4},
          {3, 10},
          {123, 10},
          {0x4, 4},
          {2, 8},
          {?A, 8},
          {?B, 8},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "123AB"
      assert length(result.chunks) == 2
      assert Enum.at(result.chunks, 0).mode == :numeric
      assert Enum.at(result.chunks, 1).mode == :byte
    end
  end

  describe "version size classes" do
    test "version 10 uses medium count bit sizes" do
      # Byte mode count is 16 bits for v10-26
      payload =
        build_payload([
          {0x4, 4},
          {3, 16},
          {?X, 8},
          {?Y, 8},
          {?Z, 8},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 10)
      assert result.text == "XYZ"
    end

    test "version 27 uses large count bit sizes" do
      # Byte mode count is 16 bits for v27-40
      payload =
        build_payload([
          {0x4, 4},
          {2, 16},
          {?!, 8},
          {??, 8},
          {0x0, 4}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 27)
      assert result.text == "!?"
    end
  end

  describe "terminator" do
    test "stops at terminator mode" do
      payload =
        build_payload([
          {0x4, 4},
          {1, 8},
          {?A, 8},
          {0x0, 4},
          {0x4, 4},
          {1, 8},
          {?B, 8}
        ])

      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "A"
    end

    test "stops when fewer than 4 bits remain" do
      payload =
        build_payload([
          {0x4, 4},
          {1, 8},
          {?Z, 8}
        ])

      # 20 bits = 2.5 bytes -> padded to 3 bytes = 24 bits, only 4 bits remain after reading
      assert {:ok, result} = DataDecoder.decode(payload, 1)
      assert result.text == "Z"
    end
  end

  describe "error handling" do
    test "returns error for unknown mode" do
      # Mode 0x3 is not defined
      payload = build_payload([{0x3, 4}, {0, 8}])
      assert {:error, "Unknown mode: 3"} = DataDecoder.decode(payload, 1)
    end
  end
end
