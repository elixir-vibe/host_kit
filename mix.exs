defmodule HostKit.MixProject do
  use Mix.Project

  def project do
    [
      app: :host_kit,
      version: "0.1.0-beta.7",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:eex, :mix, :ssh, :yaml_elixir, :yamerl]],
      package: package(),
      description: description(),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [
      mod: {HostKit.Application, []},
      extra_applications: [:logger, :ssh, :ssl, :inets]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:pi_bridge, "== 0.6.21", only: :dev},
      {:release_kit, "~> 0.3", optional: true},
      {:systemdkit, "~> 0.1.4"},
      {:unitctl, "~> 0.1.0"},
      {:dsl, "~> 0.1"},
      {:jason, "~> 1.4"},
      {:json_codec, "~> 0.1.4"},
      {:jsonpatch, "~> 2.3"},
      {:yaml_elixir, "~> 2.11"},
      {:ymlr, "~> 5.1"},
      {:toml, "~> 0.7"},
      {:req, "~> 0.5"},
      {:hammer, "~> 7.0"},
      {:dotenvy, "~> 1.1"},
      {:bash, "~> 0.5.1"},
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Elixir-native host management with inspectable plans, package locks, systemd isolation, and remote bootstrap."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/elixir-vibe/host_kit"},
      files:
        ~w(lib guides examples notebooks scripts .formatter.exs mix.exs README.md CHANGELOG.md LICENSE*)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/elixir-vibe/host_kit",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/introduction/getting-started.md",
        "guides/introduction/conventions-and-paths.md",
        "guides/deployment/remote-bootstrap.md",
        "guides/deployment/systemd-isolation.md",
        "guides/deployment/firewall-and-networking.md",
        "guides/deployment/gatehouse.md",
        "guides/workspaces/workspaces-and-tenants.md",
        "guides/operations/observability-and-monitors.md",
        "guides/operations/timers-and-jobs.md",
        "guides/reference/cli.md",
        "guides/reference/dsl-guidelines.md",
        "guides/reference/full-reference.md",
        "guides/reference/internal-architecture.md",
        "guides/reference/release-design.md",
        "guides/reference/parallel-apply-design.md",
        "notebooks/learn/deploy_caddy_site.livemd",
        "notebooks/learn/deploy_phoenix_app.livemd"
      ],
      groups_for_extras: [
        Introduction: ~r/guides\/introduction\//,
        Deployment: ~r/guides\/deployment\//,
        Workspaces: ~r/guides\/workspaces\//,
        Operations: ~r/guides\/operations\//,
        Reference: ~r/guides\/reference\//
      ]
    ]
  end

  defp aliases do
    [
      ci: [
        "format",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "test",
        "credo --strict",
        "dialyzer",
        "ex_dna --max-clones 0",
        "reach.check --arch --smells"
      ]
    ]
  end
end
