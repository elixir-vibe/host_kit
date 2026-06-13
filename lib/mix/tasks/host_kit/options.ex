defmodule Mix.Tasks.HostKit.Options do
  @moduledoc false

  def target_opts(opts) do
    case Keyword.get(opts, :remote) do
      nil -> local_target_opts(opts)
      host -> remote_target_opts(host, opts)
    end
  end

  def with_target_opts(opts, fun) do
    case Keyword.get(opts, :remote) do
      nil -> fun.(target_opts(opts))
      host -> with_remote_target_opts(host, opts, fun)
    end
  end

  def ignored_resources(opts) do
    opts
    |> Keyword.get_values(:ignore)
    |> Enum.map(&parse_resource_id/1)
  end

  def put_repology_cache(plan_opts, opts) do
    plan_opts
    |> put_present(:repology_cache_dir, Keyword.get(opts, :repology_cache))
    |> put_present(:repology_cache_ttl, cache_ttl(opts))
    |> put_present(:repology_cache, cache_enabled(opts))
  end

  defp local_target_opts(opts) do
    if Keyword.get(opts, :local, false) do
      [reader: HostKit.Local, sudo: Keyword.get(opts, :sudo, false)]
    else
      []
    end
  end

  defp remote_target_opts(host, opts) do
    target = HostKit.Target.ssh(:remote, remote_options(host, opts))

    [target: target, reader: HostKit.Remote]
  end

  defp with_remote_target_opts(host, opts, fun) do
    remote_opts = remote_options(host, opts)

    case HostKit.Runner.SSH.Connection.open(remote_opts) do
      {:ok, conn} ->
        try do
          target =
            HostKit.Target.ssh(:remote,
              runner: {HostKit.Runner.SSH.Connection, conn: conn},
              sudo: Keyword.get(opts, :sudo, false)
            )

          fun.(target: target, reader: HostKit.Remote)
        after
          HostKit.Runner.SSH.Connection.close(conn)
        end

      {:error, reason} ->
        Mix.raise("could not connect to remote target #{host}: #{inspect(reason)}")
    end
  end

  defp cache_ttl(opts) do
    case Keyword.get(opts, :repology_cache_ttl) do
      nil -> nil
      seconds -> seconds * 1000
    end
  end

  defp cache_enabled(opts) do
    if Keyword.get(opts, :repology_no_cache, false), do: false, else: nil
  end

  defp remote_options(host, opts) do
    [host: host, sudo: Keyword.get(opts, :sudo, false)]
    |> put_present(:user, Keyword.get(opts, :user))
    |> put_present(:port, Keyword.get(opts, :port))
    |> put_present(:identity_file, Keyword.get(opts, :identity_file))
    |> put_present(:password, password(opts))
    |> put_silently_accept_hosts(opts)
  end

  defp password(opts) do
    case {Keyword.get(opts, :password), Keyword.get(opts, :password_env)} do
      {password, nil} ->
        password

      {nil, env_var} ->
        case System.fetch_env(env_var) do
          {:ok, password} -> password
          :error -> Mix.raise("environment variable #{env_var} is not set")
        end

      {_password, env_var} ->
        Mix.raise("pass either --password or --password-env #{env_var}, not both")
    end
  end

  defp put_silently_accept_hosts(remote_opts, opts) do
    if Keyword.get(opts, :silently_accept_hosts, false) do
      Keyword.put(remote_opts, :silently_accept_hosts, true)
    else
      remote_opts
    end
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
