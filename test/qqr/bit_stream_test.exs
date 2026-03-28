defmodule QQR.BitStreamTest do
  use ExUnit.Case, async: true

  alias QQR.BitStream

  describe "new/1" do
    test "creates from a list of bytes" do
      stream = BitStream.new([0xFF, 0x00])
      assert BitStream.available(stream) == 16
    end

    test "creates from a binary" do
      stream = BitStream.new(<<0xFF, 0x00>>)
      assert BitStream.available(stream) == 16
    end
  end

  describe "read_bits/2" do
    test "reads single bits" do
      stream = BitStream.new([0b10110000])
      {:ok, b1, stream} = BitStream.read_bits(stream, 1)
      {:ok, b2, stream} = BitStream.read_bits(stream, 1)
      {:ok, b3, stream} = BitStream.read_bits(stream, 1)
      {:ok, b4, _stream} = BitStream.read_bits(stream, 1)
      assert [b1, b2, b3, b4] == [1, 0, 1, 1]
    end

    test "reads a full byte" do
      stream = BitStream.new([0xAB])
      {:ok, val, stream} = BitStream.read_bits(stream, 8)
      assert val == 0xAB
      assert BitStream.available(stream) == 0
    end

    test "reads across byte boundaries" do
      stream = BitStream.new([0b11110000, 0b10101010])
      {:ok, _, stream} = BitStream.read_bits(stream, 4)
      {:ok, val, _stream} = BitStream.read_bits(stream, 8)
      assert val == 0b00001010
    end

    test "reads multiple sizes sequentially" do
      stream = BitStream.new([0b01001000, 0b01100101])
      {:ok, v4, stream} = BitStream.read_bits(stream, 4)
      {:ok, v8, stream} = BitStream.read_bits(stream, 8)
      {:ok, v4b, _stream} = BitStream.read_bits(stream, 4)
      assert v4 == 0b0100
      assert v8 == 0b10000110
      assert v4b == 0b0101
    end

    test "reads 32 bits at once" do
      stream = BitStream.new([0xFF, 0x00, 0xAB, 0xCD])
      {:ok, val, stream} = BitStream.read_bits(stream, 32)
      assert val == 0xFF00ABCD
      assert BitStream.available(stream) == 0
    end

    test "returns :error when not enough bits" do
      stream = BitStream.new([0xFF])
      assert :error = BitStream.read_bits(stream, 9)
    end

    test "returns :error after exhaustion" do
      stream = BitStream.new([0xFF])
      {:ok, _, stream} = BitStream.read_bits(stream, 8)
      assert :error = BitStream.read_bits(stream, 1)
    end
  end

  describe "available/1" do
    test "returns total bits for fresh stream" do
      assert BitStream.available(BitStream.new([1, 2, 3])) == 24
    end

    test "decreases after reads" do
      stream = BitStream.new([0xFF, 0xFF])
      assert BitStream.available(stream) == 16
      {:ok, _, stream} = BitStream.read_bits(stream, 5)
      assert BitStream.available(stream) == 11
      {:ok, _, stream} = BitStream.read_bits(stream, 11)
      assert BitStream.available(stream) == 0
    end

    test "returns 0 for empty stream" do
      assert BitStream.available(BitStream.new([])) == 0
    end
  end
end
