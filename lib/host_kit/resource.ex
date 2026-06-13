defmodule HostKit.Resource do
  @moduledoc "Helpers for resource identity, dependency metadata, and JSON-safe terms."

  @callback id(struct()) :: term()

  @artifact_modules MapSet.new([
                      HostKit.Addr.AbsResource,
                      HostKit.Addr.Resource,
                      HostKit.Caddy.Directive.Encode,
                      HostKit.Caddy.Directive.FileServer,
                      HostKit.Caddy.Directive.ReverseProxy,
                      HostKit.Caddy.Directive.Root,
                      HostKit.Caddy.Site,
                      HostKit.Change,
                      HostKit.Conventions,
                      HostKit.Firewall,
                      HostKit.Firewall.Rule,
                      HostKit.Host,
                      HostKit.Package.Resolution,
                      HostKit.Project,
                      HostKit.ProviderConfig,
                      HostKit.Proxy,
                      HostKit.Resources.Capability,
                      HostKit.Resources.Directory,
                      HostKit.Resources.EnvFile,
                      HostKit.Resources.File,
                      HostKit.Resources.Mise,
                      HostKit.Resources.Package,
                      HostKit.Resources.User,
                      HostKit.Service,
                      HostKit.Systemd.Service,
                      HostKit.Systemd.Timer,
                      HostKit.Tenant,
                      HostKit.Workspace.Egress
                    ])
  @artifact_module_names @artifact_modules |> Enum.map(&Atom.to_string/1) |> MapSet.new()
  @spec id(struct()) :: term()
  def id(resource) do
    Code.ensure_loaded?(resource.__struct__)

    if function_exported?(resource.__struct__, :id, 1) do
      resource.__struct__.id(resource)
    else
      Map.fetch!(resource, :id)
    end
  end

  @spec dump(term()) :: term()
  def dump(%module{} = struct) do
    module = allowed_artifact_module!(module)

    %{
      "$type" => "struct",
      "module" => Atom.to_string(module),
      "fields" => dump(Map.from_struct(struct))
    }
  end

  def dump(tuple) when is_tuple(tuple) do
    %{"$type" => "tuple", "items" => tuple |> Tuple.to_list() |> dump()}
  end

  def dump(%{} = map) do
    %{
      "$type" => "map",
      "entries" => Enum.map(map, fn {key, value} -> [dump(key), dump(value)] end)
    }
  end

  def dump(values) when is_list(values), do: Enum.map(values, &dump/1)
  def dump(value) when is_atom(value), do: %{"$type" => "atom", "value" => Atom.to_string(value)}
  def dump(value), do: value

  @spec load(term()) :: term()
  def load(%{"$type" => "struct", "module" => module, "fields" => fields}) do
    module = allowed_artifact_module!(module)
    struct(module, load(fields))
  end

  def load(%{"$type" => "tuple", "items" => items}), do: items |> load() |> List.to_tuple()

  def load(%{"$type" => "map", "entries" => entries}) do
    Map.new(entries, fn [key, value] -> {load(key), load(value)} end)
  end

  def load(%{"$type" => "atom", "value" => value}), do: load_atom(value)
  def load(values) when is_list(values), do: Enum.map(values, &load/1)
  def load(value), do: value

  defp load_atom("autoconf"), do: :autoconf
  defp load_atom("ca_certificates"), do: :ca_certificates
  defp load_atom("capability"), do: :capability
  defp load_atom("create"), do: :create
  defp load_atom("curl"), do: :curl
  defp load_atom("cxx_compiler"), do: :cxx_compiler
  defp load_atom("delete"), do: :delete
  defp load_atom("directory"), do: :directory
  defp load_atom("drift"), do: :drift
  defp load_atom("elixir"), do: :elixir
  defp load_atom("erlang"), do: :erlang
  defp load_atom("file"), do: :file
  defp load_atom("gcc"), do: :gcc
  defp load_atom("git"), do: :git
  defp load_atom("in_sync"), do: :in_sync
  defp load_atom("lock"), do: :lock
  defp load_atom("m4"), do: :m4
  defp load_atom("make"), do: :make
  defp load_atom("missing"), do: :missing
  defp load_atom("mise"), do: :mise
  defp load_atom("ncurses_dev"), do: :ncurses_dev
  defp load_atom("no_op"), do: :no_op
  defp load_atom("openssl_dev"), do: :openssl_dev
  defp load_atom("package"), do: :package
  defp load_atom("perl"), do: :perl
  defp load_atom("read"), do: :read
  defp load_atom("semantic"), do: :semantic
  defp load_atom("systemd_service"), do: :systemd_service
  defp load_atom("systemd_timer"), do: :systemd_timer
  defp load_atom("unzip"), do: :unzip
  defp load_atom("update"), do: :update
  defp load_atom("xsltproc"), do: :xsltproc

  defp load_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp allowed_artifact_module!(module) when is_atom(module) do
    if MapSet.member?(@artifact_modules, module) do
      module
    else
      raise ArgumentError, "unsupported HostKit artifact module #{inspect(module)}"
    end
  end

  defp allowed_artifact_module!(module) when is_binary(module) do
    if MapSet.member?(@artifact_module_names, module) do
      String.to_existing_atom(module)
    else
      raise ArgumentError, "unsupported HostKit artifact module #{inspect(module)}"
    end
  end
end
