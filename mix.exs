defmodule ActiveMemory.MixProject do
  use Mix.Project

  def project do
    [
      app: :active_memory,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Make ETS and Mnesia easier to use",
      package: %{
        licenses: [],
        links: []
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    []
  end
end
