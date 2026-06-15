defmodule HostKit.Apply do
  @moduledoc "Applies supported HostKit plan changes."

  alias HostKit.{Change, Firewall, Instance, Plan, Provider, Proxy, Resources, Runner, Systemd}
  alias HostKit.Package.Manager
  alias HostKit.Runner.SSH.Connection

  alias Resources.{
    Account,
    Command,
    Directory,
    EnvFile,
    File,
    Mise,
    Package,
    Readiness,
    Shell,
    Source,
    Symlink
  }

  alias Runner.Ops

  @type result :: %{change: Change.t(), status: :dry_run | :applied | :skipped}

  @spec run(Plan.t(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def run(%Plan{} = plan, opts \\ []) do
    opts =
      plan.opts
      |> Keyword.merge(opts)
      |> Keyword.put_new(:project, plan.project)
      |> maybe_put_package_manager(plan)

    with :ok <- confirm(opts) do
      opts = Keyword.put(opts, :plan, plan)
      with_reusable_runner(opts, fn opts -> apply_changes(plan.changes, opts) end)
    end
  end

  defp maybe_put_package_manager(opts, plan) do
    if package_changes?(plan.changes) and not Keyword.has_key?(opts, :package_manager) do
      case Manager.detect(opts) do
        {:ok, manager} -> Keyword.put(opts, :package_manager, manager)
        {:error, _reason} -> opts
      end
    else
      opts
    end
  end

  defp package_changes?(changes) do
    Enum.any?(changes, &match?(%Change{after: %Package{}}, &1))
  end

  defp confirm(opts) do
    cond do
      Keyword.get(opts, :dry_run, false) -> :ok
      Keyword.get(opts, :confirm, false) -> :ok
      true -> {:error, :confirmation_required}
    end
  end

  defp with_reusable_runner(opts, fun) do
    case reusable_ssh_opts(opts) do
      {:ok, ssh_opts} ->
        case Connection.open(ssh_opts) do
          {:ok, conn} ->
            try do
              opts
              |> Keyword.put(:runner, {Connection, conn: conn})
              |> fun.()
            after
              Connection.close(conn)
            end

          {:error, reason} ->
            {:error, {:ssh_connect_failed, reason}}
        end

      :skip ->
        fun.(opts)
    end
  end

  defp reusable_ssh_opts(opts) do
    case Keyword.get(opts, :runner, HostKit.Runner.Local) do
      HostKit.Runner.SSH -> {:ok, opts}
      {HostKit.Runner.SSH, runner_opts} -> {:ok, Keyword.merge(runner_opts, opts)}
      {Connection, _runner_opts} -> :skip
      _runner -> :skip
    end
  end

  defp apply_changes(changes, opts) do
    emit(opts, :apply_started)

    changes
    |> chunk_package_changes()
    |> Enum.reduce_while({:ok, [], false}, &apply_change_chunk(&1, &2, opts))
    |> then(fn
      {:ok, results, reload?} ->
        results = Enum.reverse(results)

        with {:ok, finished} <- finish_apply(results, reload?, opts),
             :ok <- HostKit.RunRecord.write(Keyword.fetch!(opts, :plan), finished, opts) do
          emit(opts, :apply_finished, result: %{results: finished})
          {:ok, finished}
        end

      error ->
        error
    end)
  end

  defp chunk_package_changes(changes), do: chunk_package_changes(changes, []) |> Enum.reverse()

  defp chunk_package_changes([], chunks), do: chunks

  defp chunk_package_changes(
         [%Change{action: action, after: %Package{}} | _rest] = changes,
         chunks
       )
       when action in [:create, :update] do
    {package_changes, rest} = Enum.split_while(changes, &batchable_package_change?/1)
    chunk_package_changes(rest, [{:package_batch, package_changes} | chunks])
  end

  defp chunk_package_changes([change | rest], chunks) do
    chunk_package_changes(rest, [{:change, change} | chunks])
  end

  defp batchable_package_change?(%Change{action: action, after: %Package{}})
       when action in [:create, :update],
       do: true

  defp batchable_package_change?(_change), do: false

  defp apply_change_chunk({:change, change}, state, opts),
    do: apply_change_step(change, state, opts)

  defp apply_change_chunk({:package_batch, [change]}, state, opts),
    do: apply_change_step(change, state, opts)

  defp apply_change_chunk({:package_batch, changes}, {:ok, results, reload?}, opts) do
    Enum.each(changes, &report_change_start(&1, opts))

    case timed_package_batch(changes, fn -> apply_package_batch(changes, opts) end) do
      :ok ->
        batch_results = Enum.map(changes, &%{change: &1, status: :applied})

        Enum.zip(changes, batch_results)
        |> Enum.each(fn {change, result} -> report_change_result(change, result, opts) end)

        {:cont, {:ok, Enum.reverse(batch_results, results), reload?}}

      {:error, reason} ->
        failed = hd(changes)
        emit(opts, :change_failed, change: failed, reason: reason)
        {:halt, {:error, {failed.resource_id, reason}}}
    end
  end

  defp apply_change_step(change, {:ok, results, reload?}, opts) do
    report_change_start(change, opts)
    opts = change_opts(change, opts)

    case timed_change(change, fn -> apply_change(change, opts) end) do
      {:ok, result} ->
        report_change_result(change, result, opts)
        {:cont, {:ok, [result | results], reload? or systemd_change?(result)}}

      {:error, reason} ->
        emit(opts, :change_failed, change: change, reason: reason)
        {:halt, {:error, {change.resource_id, reason}}}
    end
  end

  defp apply_package_batch(changes, opts) do
    changes
    |> Enum.map(& &1.after)
    |> HostKit.Package.install_many(opts)
  end

  defp timed_package_batch(changes, fun) do
    HostKit.Telemetry.span(
      [:apply, :package_batch],
      %{resource_ids: Enum.map(changes, & &1.resource_id), count: length(changes)},
      fun
    )
  end

  defp timed_change(%Change{} = change, fun) do
    HostKit.Telemetry.span(
      [:apply, :resource],
      %{resource_id: change.resource_id, action: change.action},
      fun
    )
  end

  defp change_opts(%Change{} = change, opts) do
    change
    |> change_resource()
    |> resource_opts(opts)
  end

  defp change_resource(%Change{after: resource}) when not is_nil(resource), do: resource
  defp change_resource(%Change{before: resource}), do: resource

  defp resource_opts(%{meta: %{target_opts: target_opts}}, opts) when is_list(target_opts) do
    target_opts
    |> expand_target_opts()
    |> then(fn resource_opts -> opts |> Keyword.drop([:conn]) |> Keyword.merge(resource_opts) end)
  end

  defp resource_opts(_resource, opts), do: opts

  defp expand_target_opts(opts) do
    case Keyword.pop(opts, :target) do
      {%HostKit.Target{} = target, opts} -> HostKit.Target.opts(target, opts)
      {_other, opts} -> opts
    end
  end

  defp apply_change(%Change{action: :no_op} = change, _opts), do: {:ok, skipped(change)}
  defp apply_change(%Change{action: :read} = change, _opts), do: {:ok, skipped(change)}

  defp apply_change(%Change{action: :delete, before: %Directory{} = directory} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_path(directory.path, [:directory], opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %File{} = file} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_path(file.path, [:file], opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %Symlink{} = symlink} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_path(symlink.path, [:file], opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %EnvFile{} = env_file} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_path(env_file.path, [:file], opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %Systemd.Service{} = service} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_systemd_unit(service.name, opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %Systemd.Timer{} = timer} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_systemd_unit(timer.name, opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %Firewall{} = firewall} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_path(firewall.path, [:file], opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %Proxy{} = proxy} = change, opts) do
    apply_or_dry_run(change, opts, fn -> delete_path(proxy.path, [:file], opts) end)
  end

  defp apply_change(%Change{action: :delete, before: %Instance{} = instance} = change, opts) do
    apply_or_dry_run(change, opts, fn -> HostKit.Instance.Backend.delete(instance, opts) end)
  end

  defp apply_change(%Change{action: :delete}, _opts), do: {:error, :delete_not_supported}

  defp apply_change(%Change{action: :create, after: %Account{} = account} = change, opts) do
    apply_or_dry_run(change, opts, fn -> apply_account(account, opts) end)
  end

  defp apply_change(%Change{action: :update, after: %Account{}}, _opts),
    do: {:error, :account_update_not_supported}

  defp apply_change(%Change{action: action, after: %Directory{} = directory} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_directory(directory, opts) end)
  end

  defp apply_change(%Change{action: action, after: %File{} = file} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_file(file, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Symlink{} = symlink} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_symlink(symlink, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Command{} = command} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_command(command, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Shell{} = shell} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_shell(shell, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Source{} = source} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> HostKit.Source.Git.apply(source, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Readiness{} = readiness} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> HostKit.Readiness.wait(readiness, opts) end)
  end

  defp apply_change(%Change{action: action, after: %EnvFile{} = env_file} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_env_file(env_file, opts) end)
  end

  defp apply_change(%Change{action: action, after: %Systemd.Service{} = service} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn ->
      with {:ok, content} <- rendered_content(service, Systemd.Service.render(service), opts) do
        apply_systemd_unit(service.name, content, opts)
      end
    end)
  end

  defp apply_change(%Change{action: action, after: %Systemd.Timer{} = timer} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn ->
      with {:ok, content} <- rendered_content(timer, Systemd.Timer.render(timer), opts) do
        apply_systemd_unit(timer.name, content, opts)
      end
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

  defp apply_change(%Change{action: action, after: %Instance{} = instance} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> HostKit.Instance.Backend.apply(instance, opts) end)
  end

  defp apply_change(
         %Change{action: action, after: %HostKit.Workspace.Egress{} = egress} = change,
         opts
       )
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_egress(egress, opts) end)
  end

  defp apply_change(%Change{} = change, opts), do: apply_provider_change(change, opts)

  defp report_change_start(%Change{action: action} = change, opts) when action in [:no_op, :read],
    do: emit(opts, :change_skipped, change: change)

  defp report_change_start(%Change{} = change, opts),
    do: emit(opts, :change_started, change: change)

  defp report_change_result(%Change{action: action}, _result, _opts)
       when action in [:no_op, :read],
       do: :ok

  defp report_change_result(%Change{} = change, result, opts),
    do: emit(opts, :change_finished, change: change, result: result)

  defp emit(opts, type, attrs \\ []) do
    attrs = maybe_put_lifecycle(attrs, opts)

    HostKit.Apply.Events.emit(opts, type, attrs)
  end

  defp maybe_put_lifecycle(attrs, opts) do
    case Keyword.get(attrs, :change) do
      %Change{after: %Command{phase: phase, name: name}} when not is_nil(phase) ->
        Keyword.put_new(attrs, :lifecycle, %{
          phase: phase,
          operation: name,
          direction: Keyword.get(opts, :direction, :up)
        })

      _other ->
        attrs
    end
  end

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
    with :ok <- HostKit.Runner.Files.mkdir_p(path, opts),
         :ok <- Ops.chown(path, directory.owner, directory.group, opts) do
      Ops.chmod(path, directory.mode, opts)
    end
  end

  defp apply_file(%File{content: content}, _opts) when content in [:redacted, :managed_elsewhere],
    do: {:error, :file_content_managed_elsewhere}

  defp apply_file(%File{path: path, content: content} = file, opts) do
    with {:ok, content} <- file_content(content, opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, opts),
         :ok <- Ops.chown(path, file.owner, file.group, opts) do
      Ops.chmod(path, file.mode, opts)
    end
  end

  defp apply_symlink(%Symlink{path: path, to: target} = symlink, opts) do
    with :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- Ops.cmd(opts, "ln", ["-sfnT", target, path]) do
      symlink_chown(path, symlink.owner, symlink.group, opts)
    end
  end

  defp symlink_chown(_path, nil, nil, _opts), do: :ok

  defp symlink_chown(path, owner, group, opts) do
    spec = [owner || "", group || ""] |> Enum.join(":") |> String.trim_trailing(":")
    Ops.cmd(opts, "chown", ["-h", spec, path])
  end

  defp rendered_content(%{meta: %{content: %HostKit.BackupRef{} = ref}}, _default, opts),
    do: file_content(ref, opts)

  defp rendered_content(_resource, default, _opts), do: {:ok, IO.iodata_to_binary(default)}

  defp file_content(%HostKit.BackupRef{path: path}, opts), do: Runner.read_file(path, opts)
  defp file_content(nil, _opts), do: {:ok, ""}
  defp file_content(content, _opts), do: {:ok, IO.iodata_to_binary(content)}

  defp apply_account(%Account{name: name} = account, opts) do
    args = if account.system, do: ["--system"], else: []
    args = if account.home, do: args ++ ["--home", account.home], else: args
    args = if account.shell, do: args ++ ["--shell", account.shell], else: args
    args = args ++ Enum.flat_map(account.groups, &["--groups", &1])

    Ops.cmd(opts, "useradd", args ++ [name])
  end

  defp apply_env_file(%EnvFile{path: path} = env_file, opts) do
    with {:ok, content} <- env_file_content(env_file, opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, opts),
         :ok <- Ops.chown(path, env_file.owner, env_file.group, opts) do
      Ops.chmod(path, env_file.mode, opts)
    end
  end

  defp env_file_content(%{meta: %{content: %HostKit.BackupRef{}}} = env_file, opts),
    do: rendered_content(env_file, "", opts)

  defp env_file_content(%EnvFile{} = env_file, opts), do: HostKit.Env.render(env_file, opts)

  defp apply_command(%Command{} = command, opts) do
    with :ok <- command_current(command, opts),
         :ok <- command_creates(command, opts),
         :ok <- command_unless(command, opts) do
      {executable, args, command_opts} = command_exec(command, opts)

      with :ok <- Ops.cmd(opts, executable, args, command_opts) do
        HostKit.RunStamp.write(command, opts)
      end
    else
      :skip -> :ok
    end
  end

  defp apply_shell(%Shell{} = shell, opts) do
    command = %Command{
      name: shell.name,
      exec: {"bash", ["-euo", "pipefail", "-c", shell.script.source]},
      cwd: shell.cwd,
      env: shell.env,
      creates: shell.creates,
      unless: shell.unless,
      timeout: shell.timeout
    }

    with :ok <- command_current(shell, opts),
         :ok <- apply_command(command, opts) do
      HostKit.RunStamp.write(shell, opts)
    else
      :skip -> :ok
    end
  end

  defp command_current(resource, opts) do
    if HostKit.RunStamp.current?(resource, opts), do: :skip, else: :ok
  end

  defp command_creates(%{creates: nil}, _opts), do: :ok

  defp command_creates(%{creates: path} = resource, opts) do
    if HostKit.RunStamp.stamp_required?(resource) do
      :ok
    else
      case Ops.cmd(opts, "test", ["-e", path]) do
        :ok -> :skip
        {:error, _reason} -> :ok
      end
    end
  end

  defp command_unless(%{unless: nil}, _opts), do: :ok

  defp command_unless(%{unless: shell}, opts) do
    case Ops.cmd(opts, "sh", ["-c", shell]) do
      :ok -> :skip
      {:error, _reason} -> :ok
    end
  end

  defp command_exec(%Command{exec: {command, args}, runtime: nil} = resource, opts) do
    command_env(command, args, command_opts(resource), opts)
  end

  defp command_exec(%Command{exec: {command, args}, runtime: {:mise, name}} = resource, opts) do
    mise = find_mise!(name, opts)
    tool_args = Enum.map(mise.tools, &"#{&1.name}@#{&1.version}")

    command_opts =
      resource
      |> command_opts()
      |> Keyword.update(:env, mise_env(mise), &Map.merge(mise_env(mise), &1))

    command_env(mise.path, ["exec"] ++ tool_args ++ ["--", command | args], command_opts, opts)
  end

  defp command_env(command, args, command_opts, opts) do
    case {Keyword.get(opts, :sudo, false), Keyword.pop(command_opts, :env)} do
      {true, {env, command_opts}} when is_map(env) and map_size(env) > 0 ->
        env_args = Enum.map(env, fn {key, value} -> "#{key}=#{value}" end)
        {"env", env_args ++ [command | args], command_opts}

      _other ->
        {command, args, command_opts}
    end
  end

  defp command_opts(%Command{} = command) do
    []
    |> maybe_put(:cd, command.cwd)
    |> maybe_put(:env, command.env)
    |> maybe_put(:timeout, command.timeout)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, value) when value == %{}, do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp find_mise!(name, opts) do
    opts
    |> Keyword.fetch!(:project)
    |> HostKit.Project.resources()
    |> Enum.find(&match?(%Mise{name: ^name}, &1)) ||
      raise ArgumentError, "unknown mise runtime #{inspect(name)}"
  end

  defp mise_env(%Mise{system_data_dir: system_data_dir}) do
    %{"MISE_NO_CONFIG" => "1", "MISE_SYSTEM_DATA_DIR" => system_data_dir}
  end

  defp apply_egress(%HostKit.Workspace.Egress{user: user} = egress, opts) do
    path =
      Keyword.get(opts, :egress_dir, "/etc/nftables.d") |> Path.join("hostkit-egress-#{user}.nft")

    with {:ok, content} <- rendered_content(egress, Firewall.Nftables.render_egress(egress), opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, opts),
         :ok <- Ops.chown(path, "root", "root", opts),
         :ok <- Ops.chmod(path, 0o644, opts) do
      validate_firewall(path, opts)
    end
  end

  defp apply_proxy(%Proxy{path: path} = proxy, opts) do
    with {:ok, content} <- rendered_content(proxy, Proxy.render(proxy), opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, opts),
         :ok <- Ops.chown(path, proxy.meta[:owner], proxy.meta[:group], opts) do
      Ops.chmod(path, Map.get(proxy.meta, :mode, 0o644), opts)
    end
  end

  defp apply_mise(%Mise{} = mise, opts), do: HostKit.Mise.install(mise, opts)

  defp apply_firewall(%Firewall{path: path} = firewall, opts) do
    with {:ok, content} <- rendered_content(firewall, Firewall.render(firewall), opts),
         :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- HostKit.Runner.Files.write_file(path, content, opts),
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
    path = systemd_unit_path(name, opts)
    owner = Keyword.get(opts, :systemd_unit_owner, "root")
    group = Keyword.get(opts, :systemd_unit_group, "root")

    with :ok <- HostKit.Runner.Files.mkdir_p(Path.dirname(path), opts),
         :ok <- HostKit.Runner.Files.write_file(path, IO.iodata_to_binary(content), opts),
         :ok <- Ops.chown(path, owner, group, opts) do
      Ops.chmod(path, 0o644, opts)
    end
  end

  defp delete_systemd_unit(name, opts),
    do: delete_path(systemd_unit_path(name, opts), [:file], opts)

  defp systemd_unit_path(name, opts),
    do: Path.join(Keyword.get(opts, :systemd_unit_dir, "/etc/systemd/system"), name)

  defp delete_path(path, [:directory], opts), do: Ops.cmd(opts, "rmdir", [path])
  defp delete_path(path, [:file], opts), do: Ops.cmd(opts, "rm", ["-f", path])

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

  defp systemd_change?(%{status: status, change: %{before: %Systemd.Service{}}})
       when status in [:applied, :dry_run],
       do: true

  defp systemd_change?(%{status: status, change: %{after: %Systemd.Timer{}}})
       when status in [:applied, :dry_run],
       do: true

  defp systemd_change?(%{status: status, change: %{before: %Systemd.Timer{}}})
       when status in [:applied, :dry_run],
       do: true

  defp systemd_change?(_result), do: false

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

  defp skipped(change), do: %{change: change, status: :skipped}
end
