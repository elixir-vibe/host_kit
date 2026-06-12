defmodule Mix.Tasks.HostKit.Options do
  @moduledoc false

  def target_opts(opts) do
    case Keyword.get(opts, :remote) do
      nil -> local_target_opts(opts)
      host -> remote_target_opts(host, opts)
    end
  end

  def ignored_resources(opts) do
    opts
    |> Keyword.get_values(:ignore)
    |> Enum.map(&parse_resource_id/1)
  end

  defp local_target_opts(opts) do
    if Keyword.get(opts, :local, false) do
      [reader: HostKit.Local, sudo: Keyword.get(opts, :sudo, false)]
    else
      []
    end
  end

  defp remote_target_opts(host, opts) do
    target_opts = [host: host, sudo: Keyword.get(opts, :sudo, false)]
    target_opts = put_present(target_opts, :user, Keyword.get(opts, :user))
    target_opts = put_present(target_opts, :port, Keyword.get(opts, :port))
    target = HostKit.Target.ssh(:remote, target_opts)

    [target: target, reader: HostKit.Remote]
  end

  defp put_present(opts, _key, nil), do: opts
  defp put_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_resource_id(resource) do
    case String.split(resource, ":", parts: 2) do
      [type, name] -> {resource_type(type), name}
      _ -> Mix.raise("invalid --ignore #{inspect(resource)}, expected type:name")
    end
  end

  defp resource_type(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> Mix.raise("unknown resource type in --ignore: #{inspect(type)}")
  end
end
