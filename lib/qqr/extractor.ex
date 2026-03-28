defmodule QQR.Extractor do
  @moduledoc false

  alias QQR.BitMatrix

  @type point :: {number(), number()}

  @type location :: %{
          top_left: point(),
          top_right: point(),
          bottom_left: point(),
          alignment_pattern: point(),
          dimension: pos_integer()
        }

  # {a11, a12, a13, a21, a22, a23, a31, a32, a33}
  @type transform ::
          {float(), float(), float(), float(), float(), float(), float(), float(), float()}

  @spec extract(BitMatrix.t(), location()) :: {BitMatrix.t(), (number(), number() -> point())}
  def extract(image, location) do
    dim = location.dimension

    q_to_s =
      quadrilateral_to_square(
        {3.5, 3.5},
        {dim - 3.5, 3.5},
        {dim - 6.5, dim - 6.5},
        {3.5, dim - 3.5}
      )

    s_to_q =
      square_to_quadrilateral(
        location.top_left,
        location.top_right,
        location.alignment_pattern,
        location.bottom_left
      )

    transform = transform_multiply(s_to_q, q_to_s)

    mapping_fn = fn x, y -> transform_point(transform, x, y) end

    matrix =
      Enum.reduce(0..(dim - 1)//1, BitMatrix.new(dim, dim), fn y, mat ->
        Enum.reduce(0..(dim - 1)//1, mat, fn x, mat2 ->
          {sx, sy} = mapping_fn.(x + 0.5, y + 0.5)
          BitMatrix.set(mat2, x, y, BitMatrix.get(image, floor(sx), floor(sy)))
        end)
      end)

    {matrix, mapping_fn}
  end

  @spec square_to_quadrilateral(point(), point(), point(), point()) :: transform()
  def square_to_quadrilateral({x1, y1}, {x2, y2}, {x3, y3}, {x4, y4}) do
    dx3 = x1 - x2 + x3 - x4
    dy3 = y1 - y2 + y3 - y4

    if dx3 == 0 and dy3 == 0 do
      {x2 - x1, y2 - y1, 0.0, x3 - x2, y3 - y2, 0.0, x1, y1, 1.0}
    else
      dx1 = x2 - x3
      dx2 = x4 - x3
      dy1 = y2 - y3
      dy2 = y4 - y3
      denominator = dx1 * dy2 - dx2 * dy1

      if abs(denominator) < 1.0e-10 do
        {x2 - x1, y2 - y1, 0.0, x4 - x1, y4 - y1, 0.0, x1 / 1, y1 / 1, 1.0}
      else
        a13 = (dx3 * dy2 - dx2 * dy3) / denominator
        a23 = (dx1 * dy3 - dx3 * dy1) / denominator

        {
          x2 - x1 + a13 * x2,
          y2 - y1 + a13 * y2,
          a13,
          x4 - x1 + a23 * x4,
          y4 - y1 + a23 * y4,
          a23,
          x1 / 1,
          y1 / 1,
          1.0
        }
      end
    end
  end

  @spec quadrilateral_to_square(point(), point(), point(), point()) :: transform()
  def quadrilateral_to_square(p1, p2, p3, p4) do
    {a11, a12, a13, a21, a22, a23, a31, a32, a33} = square_to_quadrilateral(p1, p2, p3, p4)

    {
      a22 * a33 - a23 * a32,
      a13 * a32 - a12 * a33,
      a12 * a23 - a13 * a22,
      a23 * a31 - a21 * a33,
      a11 * a33 - a13 * a31,
      a13 * a21 - a11 * a23,
      a21 * a32 - a22 * a31,
      a12 * a31 - a11 * a32,
      a11 * a22 - a12 * a21
    }
  end

  @spec transform_multiply(transform(), transform()) :: transform()
  def transform_multiply(
        {a11, a12, a13, a21, a22, a23, a31, a32, a33},
        {b11, b12, b13, b21, b22, b23, b31, b32, b33}
      ) do
    {
      a11 * b11 + a21 * b12 + a31 * b13,
      a12 * b11 + a22 * b12 + a32 * b13,
      a13 * b11 + a23 * b12 + a33 * b13,
      a11 * b21 + a21 * b22 + a31 * b23,
      a12 * b21 + a22 * b22 + a32 * b23,
      a13 * b21 + a23 * b22 + a33 * b23,
      a11 * b31 + a21 * b32 + a31 * b33,
      a12 * b31 + a22 * b32 + a32 * b33,
      a13 * b31 + a23 * b32 + a33 * b33
    }
  end

  @spec transform_point(transform(), number(), number()) :: point()
  def transform_point({a11, a12, a13, a21, a22, a23, a31, a32, a33}, x, y) do
    denominator = a13 * x + a23 * y + a33
    denominator = if abs(denominator) < 1.0e-10, do: 1.0e-10, else: denominator
    {(a11 * x + a21 * y + a31) / denominator, (a12 * x + a22 * y + a32) / denominator}
  end
end
