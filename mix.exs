defmodule ActiveMemory.MixProject do
  use Mix.Project

  @app :active_memory
  @author "Erin Boeger"
  @github "https://github.com/SullysMustyRuby/active_memory"
  @license "MIT"
  @name "ActiveMemory"
  @version "0.2.6"

  def project do
    [
      app: @app,
      version: @version,
      author: @author,
      description: description(),
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

      # ExDoc
      name: @name,
      source_url: @github,
      homepage_url: @github,
      docs: [
        main: @name,
        canonical: "https://hexdocs.pm/#{@app}",
        extras: ["README.md"]
      ],
      aliases: [
        test: "test --no-start"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mnesia]
    ]
  end

  defp description do
    "A Simple ORM for ETS and Mnesia"
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:local_cluster, "~> 1.2", only: [:test]},
      {:uuid, "~> 1.1"}
    ]
  end

  defp package do
    [
      name: @app,
      maintainers: [@author],
      licenses: [@license],
      files: ~w(mix.exs lib README.md),
      links: %{"Github" => @github}
    ]
  end
end
