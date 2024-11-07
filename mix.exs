defmodule Please.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :please,
      name: "Please",
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      source_url: "https://github.com/quarkex/elixir-please",
      description: description(),
      package: package(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Please.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:elixir_uuid, "~> 1.2"}
    ]
  end

  defp description do
    """
    Elixir node mesh network for request balancing.
    """
  end

  def docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}"
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Manlio García"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/quarkex/elixir-please"}
    ]
  end
end
