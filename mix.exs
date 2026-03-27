defmodule QQR.MixProject do
  use Mix.Project

  def project do
    [
      app: :qqr,
      version: "0.1.0",
      description: "Pure Elixir QR code decoder",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:qr_code, "~> 3.0", only: :test}
    ]
  end
end
