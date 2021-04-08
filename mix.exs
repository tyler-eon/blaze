defmodule Blaze.MixProject do
  use Mix.Project

  def project do
    [
      app: :blaze,
      description: "A friendlier interface to Google Cloud Firestore.",
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      source_url: "https://github.com/kolorahl/blaze",
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:google_api_firestore, "~> 0.21"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
    ]
  end

  defp package do
    [
      licenses: [
        "GNU GPLv3",
      ],
      links: %{
        "GitHub" => "https://github.com/kolorahl/blaze"
      },
    ]
  end
end
