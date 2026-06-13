defmodule HostKit.Firewall do
  @moduledoc "Declarative host firewall policy."

  alias HostKit.Firewall.Rule
  alias HostKit.Project

  @type t :: %__MODULE__{
          rules: [Rule.t()],
          scope: :project | :host,
          name: atom() | nil,
          path: String.t(),
          depends_on: [term()],
          meta: map()
        }

  defstruct rules: [],
            scope: :project,
            name: nil,
            path: "/etc/nftables.d/hostkit.nft",
            depends_on: [],
            meta: %{}

  def id(%__MODULE__{path: path}), do: {:firewall, path}

  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = firewall), do: HostKit.Firewall.Nftables.render(firewall)

  @spec allow(keyword()) :: Rule.t()
  def allow(opts) do
    {protocol, ports} = protocol_ports(opts)

    %Rule{
      action: :allow,
      protocol: protocol,
      ports: List.wrap(ports),
      from: Keyword.get(opts, :from, :any),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec deny(term(), keyword()) :: Rule.t()
  def deny(target, opts \\ []) do
    %Rule{
      action: :deny,
      target: target,
      from: Keyword.get(opts, :from),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec policies(Project.t()) :: [t()]
  def policies(%Project{} = project) do
    project_policy =
      project.meta
      |> Map.get(:firewall)
      |> List.wrap()
      |> Enum.map(&%{&1 | scope: :project})

    host_policies =
      Enum.flat_map(project.hosts, fn host ->
        host.meta
        |> Map.get(:firewall)
        |> List.wrap()
        |> Enum.map(&%{&1 | scope: :host, name: host.name})
      end)

    project_policy ++ host_policies
  end

  defp protocol_ports(opts) do
    cond do
      Keyword.has_key?(opts, :tcp) -> {:tcp, Keyword.fetch!(opts, :tcp)}
      Keyword.has_key?(opts, :udp) -> {:udp, Keyword.fetch!(opts, :udp)}
      Keyword.has_key?(opts, :icmp) -> {:icmp, Keyword.fetch!(opts, :icmp)}
      true -> raise ArgumentError, "allow requires :tcp, :udp, or :icmp"
    end
  end
end
