defmodule HostKit.Apply do
  @moduledoc "Applies supported HostKit plan changes."

  alias HostKit.{Change, Firewall, Plan, Provider, Proxy, Resources, Runner, Systemd}
  alias Resources.{Directory, EnvFile, File, Mise, Package, User}
  alias Runner.Ops

  @type result :: %{change: Change.t(), status: :dry_run | :applied | :skipped}

  @spec run(Plan.t(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def run(%Plan{} = plan, opts \\ []) do
    opts = Keyword.put_new(opts, :project, plan.project)

    with :ok <- confirm(opts) do
      apply_changes(plan.changes, opts)
    end
  end

  defp confirm(opts) do
    cond do
      Keyword.get(opts, :dry_run, false) -> :ok
      Keyword.get(opts, :confirm, false) -> :ok
      true -> {:error, :confirmation_required}
    end
  end

  defp apply_changes(changes, opts) do
    changes
    |> Enum.reduce_while({:ok, [], false}, fn change, {:ok, results, reload?} ->
      case apply_change(change, opts) do
        {:ok, result} -> {:cont, {:ok, [result | results], reload? or systemd_change?(result)}}
        {:error, reason} -> {:halt, {:error, {change.resource_id, reason}}}
      end
    end)
    |> then(fn
      {:ok, results, reload?} -> finish_apply(Enum.reverse(results), reload?, opts)
      error -> error
    end)
  end

  defp apply_change(%Change{action: :no_op} = change, _opts), do: {:ok, skipped(change)}
  defp apply_change(%Change{action: :read} = change, _opts), do: {:ok, skipped(change)}
  defp apply_change(%Change{action: :delete}, _opts), do: {:error, :delete_not_supported}

  defp apply_change(%Change{action: :create, after: %User{} = user} = change, opts) do
    apply_or_dry_run(change, opts, fn -> apply_user(user, opts) end)
  end

  defp apply_change(%Change{action: :update, after: %User{}}, _opts),
    do: {:error, :user_update_not_supported}

  defp apply_change(%Change{action: action, after: %Directory{} = directory} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_directory(directory, opts) end)
  end

  defp apply_change(%Change{action: action, after: %File{} = file} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_file(file, opts) end)
  end

  defp apply_change(%Change{action: action, after: %EnvFile{} = env_file} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_env_file(env_file, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Systemd.Service{} = service} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn ->
      apply_systemd_unit(service.name, Systemd.Service.render(service), opts)
    end)
  end

  defp apply_change(%Change{action: action, after: %Systemd.Timer{} = timer} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn ->
      apply_systemd_unit(timer.name, Systemd.Timer.render(timer), opts)
    end)
  end

  defp apply_change(%Change{action: action, after: %Firewall{} = firewall} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_firewall(firewall, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Proxy{} = proxy} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_proxy(proxy, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Mise{} = mise} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_mise(mise, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Package{} = package} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> HostKit.Package.install(package, opts) end)
  end

  defp apply_change(
         %Change{action: action, after: %HostKit.Workspace.Egress{} = egress} = change,
         opts
       )
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_egress(egress, opts) end)
  end

  defp apply_change(%Change{} = change, opts), do: apply_provider_change(change, opts)

  defp apply_or_dry_run(change, opts, fun) do
    if Keyword.get(opts, :dry_run, false) do
      {:ok, %{change: change, status: :dry_run}}
    else
      with :ok <- fun.() do
        {:ok, %{change: change, status: :applied}}
      end
    end
  end

  defp apply_directory(%Directory{path: path} = directory, opts) do
    with :ok <- mkdir_p(path, opts),
         :ok <- Ops.chown(path, directory.owner, directory.group, opts) do
      Ops.chmod(path, directory.mode, opts)
    end
  end

  defp apply_file(%File{content: content}, _opts) when content in [:redacted, :managed_elsewhere],
    do: {:error, :file_content_managed_elsewhere}

  defp apply_file(%File{path: path, content: content} = file, opts) do
    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, IO.iodata_to_binary(content || ""), opts),
         :ok <- Ops.chown(path, file.owner, file.group, opts) do
      Ops.chmod(path, file.mode, opts)
    end
  end

  defp apply_user(%User{name: name} = user, opts) do
    args = if user.system, do: ["--system"], else: []
    args = if user.home, do: args ++ ["--home", user.home], else: args
    args = if user.shell, do: args ++ ["--shell", user.shell], else: args
    args = args ++ Enum.flat_map(user.groups, &["--groups", &1])

    Ops.cmd(opts, "useradd", args ++ [name])
  end

  defp apply_env_file(%EnvFile{path: path} = env_file, opts) do
    with {:ok, content} <- HostKit.Env.render(env_file, opts),
         :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, content, opts),
         :ok <- Ops.chown(path, env_file.owner, env_file.group, opts) do
      Ops.chmod(path, env_file.mode, opts)
    end
  end

  defp apply_egress(%HostKit.Workspace.Egress{user: user} = egress, opts) do
    path =
      Keyword.get(opts, :egress_dir, "/etc/nftables.d") |> Path.join("hostkit-egress-#{user}.nft")

    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, Firewall.Nftables.render_egress(egress), opts),
         :ok <- Ops.chown(path, "root", "root", opts),
         :ok <- Ops.chmod(path, 0o644, opts) do
      validate_firewall(path, opts)
    end
  end

  defp apply_proxy(%Proxy{path: path} = proxy, opts) do
    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, Proxy.render(proxy), opts),
         :ok <- Ops.chown(path, proxy.meta[:owner], proxy.meta[:group], opts) do
      Ops.chmod(path, Map.get(proxy.meta, :mode, 0o644), opts)
    end
  end

  defp apply_mise(%Mise{} = mise, opts), do: HostKit.Mise.install(mise, opts)

  defp apply_firewall(%Firewall{path: path} = firewall, opts) do
    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, Firewall.render(firewall), opts),
         :ok <- Ops.chown(path, "root", "root", opts),
         :ok <- Ops.chmod(path, 0o644, opts),
         :ok <- validate_firewall(path, opts) do
      reload_firewall(opts)
    end
  end

  defp validate_firewall(path, opts) do
    if Keyword.get(opts, :nft_validate, true) do
      Ops.cmd(opts, "nft", ["-c", "-f", path])
    else
      :ok
    end
  end

  defp reload_firewall(opts) do
    if Keyword.get(opts, :nft_reload, false) do
      Ops.cmd(opts, "nft", ["-f", Keyword.get(opts, :nft_config, "/etc/nftables.conf")])
    else
      :ok
    end
  end

  defp apply_systemd_unit(name, content, opts) do
    path = Path.join(Keyword.get(opts, :systemd_unit_dir, "/etc/systemd/system"), name)
    owner = Keyword.get(opts, :systemd_unit_owner, "root")
    group = Keyword.get(opts, :systemd_unit_group, "root")

    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, IO.iodata_to_binary(content), opts),
         :ok <- Ops.chown(path, owner, group, opts) do
      Ops.chmod(path, 0o644, opts)
    end
  end

  defp finish_apply(results, true, opts) do
    if Keyword.get(opts, :dry_run, false) do
      {:ok, results}
    else
      with :ok <- daemon_reload(opts) do
        {:ok, results}
      end
    end
  end

  defp finish_apply(results, false, _opts), do: {:ok, results}

  defp daemon_reload(opts) do
    if Keyword.get(opts, :systemd_daemon_reload, true) do
      Ops.cmd(opts, "systemctl", ["daemon-reload"])
    else
      :ok
    end
  end

  defp systemd_change?(%{status: status, change: %{after: %Systemd.Service{}}})
       when status in [:applied, :dry_run],
       do: true

  defp systemd_change?(%{status: status, change: %{after: %Systemd.Timer{}}})
       when status in [:applied, :dry_run],
       do: true

  defp systemd_change?(_result), do: false

  defp mkdir_p(path, opts) do
    opts |> runner() |> Runner.mkdir_p(path, opts)
  end

  defp write_file(path, content, opts) do
    opts |> runner() |> Runner.write_file(path, content, opts)
  end

  defp apply_provider_change(%Change{} = change, opts) do
    case Keyword.fetch(opts, :project) do
      {:ok, project} ->
        apply_or_dry_run(change, opts, fn ->
          Provider.apply(project.providers, change, %{project: project, opts: opts})
        end)

      :error ->
        {:error, {:unsupported_resource, change.resource_id}}
    end
  end

  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)

  defp skipped(change), do: %{change: change, status: :skipped}
end
