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
                      HostKit.CommandLine,
                      HostKit.Conventions,
                      HostKit.Firewall,
                      HostKit.Firewall.Rule,
                      HostKit.Host,
                      HostKit.Package.Resolution,
                      HostKit.Project,
                      HostKit.ProviderConfig,
                      HostKit.Proxy,
                      HostKit.Resources.Capability,
                      HostKit.Resources.Command,
                      HostKit.Resources.Directory,
                      HostKit.Resources.EnvFile,
                      HostKit.Resources.File,
                      HostKit.Resources.Mise,
                      HostKit.Resources.Package,
                      HostKit.Resources.Shell,
                      HostKit.Resources.Source,
                      HostKit.Resources.User,
                      HostKit.Secret,
                      HostKit.Service,
                      HostKit.ShellScript,
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
