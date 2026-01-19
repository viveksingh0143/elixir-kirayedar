defmodule Kirayedar.MixProject do
  use Mix.Project

  @name "Kirayedar"
  @package_name "kirayedar"
  @version "0.1.0"
  @source_url "https://github.com/viveksingh0143/elixir-kirayedar"
  def project do
    [
      app: :kirayedar,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      package: package(),
      aliases: aliases(),
      source_url: @source_url,
      name: @name,
      description: description(),
      docs: docs()
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
      # Core database logic
      {:ecto_sql, "~> 3.13"},
      {:jason, "~> 1.4"},
      {:phoenix, "~> 1.8", optional: true},
      {:plug, "~> 1.19"},
      # Test & Dev only
      {:postgrex, "~> 0.22", optional: true},
      {:myxql, "~> 0.8", optional: true},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    Multi-tenancy library for Elixir/Phoenix with schema-based isolation
    (PostgreSQL Schemas or MySQL Databases). Lightweight, observable,
    with clean separation of concerns.
    """
  end

  defp package() do
    [
      name: @package_name,
      maintainers: ["Vivek Singh"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv .formatter.exs mix.exs README* LICENSE*)
    ]
  end

  defp docs do
    [
      main: @name,
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp aliases do
    [
      # test: ["ecto.create --quiet -r Kirayedar.TestRepo.Postgres", "test"]
    ]
  end
end
