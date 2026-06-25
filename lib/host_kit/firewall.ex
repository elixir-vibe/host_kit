defmodule HostKit.Firewall do
  @moduledoc "Declarative host firewall policy."

  alias HostKit.{Conventions, Naming, Project, Systemd}
  alias HostKit.Firewall.Rule

  @type t :: %__MODULE__{
          rules: [Rule.t()],
          scope: :project | :host,
          name: atom() | nil,
          path: String.t(),
          activate: false | :systemd,
          depends_on: [term()],
          meta: map()
        }

  defstruct rules: [],
            scope: :project,
            name: nil,
            path: "/etc/nftables.d/hostkit.nft",
            activate: :systemd,
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

  @spec resources(Project.t()) :: [struct()]
  def resources(%Project{} = project) do
    firewalls = policies(project)
    firewalls ++ Enum.flat_map(firewalls, &activation_resources(&1, project))
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

  defp activation_resources(%__MODULE__{activate: :systemd} = firewall, %Project{} = project) do
    [
      Systemd.Service.new(systemd_unit_name(firewall, project),
        unit: [
          description:
            Map.get(firewall.meta, :description, "Load HostKit nftables firewall policy"),
          after: Map.get(firewall.meta, :after, ["network-pre.target"]),
          before: Map.get(firewall.meta, :before, ["network.target"]),
          wants: Map.get(firewall.meta, :wants, ["network-pre.target"])
        ],
        service: [
          type: :oneshot,
          exec_start: nft_command(firewall) ++ ["-f", firewall.path],
          remain_after_exit: true
        ],
        install: [wanted_by: Map.get(firewall.meta, :wanted_by, :multi_user)],
        depends_on: [id(firewall)]
      )
    ]
  end

  defp activation_resources(%__MODULE__{activate: false}, %Project{}), do: []
  defp activation_resources(%__MODULE__{activate: nil}, %Project{}), do: []

  defp systemd_unit_name(%__MODULE__{meta: %{unit: unit}}, _project) when not is_nil(unit),
    do: Naming.systemd_unit(unit)

  defp systemd_unit_name(%__MODULE__{scope: :host, name: name}, %Project{} = project)
       when not is_nil(name) do
    project.conventions
    |> Conventions.prefixed(:unit, "#{Naming.identity_segment(name)}-firewall")
    |> Naming.systemd_unit()
  end

  defp systemd_unit_name(%__MODULE__{}, %Project{} = project) do
    project.conventions
    |> Conventions.prefixed(:unit, "firewall")
    |> Naming.systemd_unit()
  end

  defp nft_command(%__MODULE__{meta: %{nft: nft}}) when is_binary(nft), do: [nft]
  defp nft_command(%__MODULE__{meta: %{nft: nft}}) when is_list(nft), do: nft
  defp nft_command(%__MODULE__{}), do: ["/usr/bin/env", "nft"]

  defp protocol_ports(opts) do
    cond do
      Keyword.has_key?(opts, :tcp) -> {:tcp, Keyword.fetch!(opts, :tcp)}
      Keyword.has_key?(opts, :udp) -> {:udp, Keyword.fetch!(opts, :udp)}
      Keyword.has_key?(opts, :icmp) -> {:icmp, Keyword.fetch!(opts, :icmp)}
      true -> raise ArgumentError, "allow requires :tcp, :udp, or :icmp"
    end
  end
end
