defmodule HelloPhoenix.MixProject do
  use Mix.Project

  def project do
    [
      app: :hello_phoenix,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: [
        hello_phoenix: [
          applications: [runtime_tools: :permanent]
        ]
      ]
    ]
  end

  def application do
    [
      mod: {HelloPhoenix.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end

  defp aliases do
    [
      "assets.deploy": fn _args -> Mix.shell().info("No assets to deploy") end
    ]
  end
end
