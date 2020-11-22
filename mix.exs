defmodule Sand.MixProject do
  use Mix.Project

  def project do
    [
      app: :sand,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Elixir sandbox",
      package: [
        licenses: ["AGPL-3.0"],
        links: %{"source" => "https://github.com/bopjesvla/sand"}
      ]

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
      {:benchee, "~> 1.0", only: [:dev, :test]},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
    ]
  end
end
