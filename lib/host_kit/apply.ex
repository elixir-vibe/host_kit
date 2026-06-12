defmodule HostKit.Apply do
  @moduledoc "Applies supported HostKit plan changes."

  alias HostKit.{Change, Plan, Runner}
  alias HostKit.Resources.{Directory, File, User}
  alias HostKit.Systemd

  @type result :: %{change: Change.t(), status: :dry_run | :applied | :skipped}

  @spec run(Plan.t(), keyword()) :: {:ok, [result()]} | {:error, term()}
  def run(%Plan{} = plan, opts \\ []) do
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

  defp apply_change(%Change{} = change, _opts),
    do: {:error, {:unsupported_resource, change.resource_id}}

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
         :ok <- chown(path, directory.owner, directory.group, opts) do
      chmod(path, directory.mode, opts)
    end
  end

  defp apply_file(%File{content: content}, _opts) when content in [:redacted, :managed_elsewhere],
    do: {:error, :file_content_managed_elsewhere}

  defp apply_file(%File{path: path, content: content} = file, opts) do
    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, IO.iodata_to_binary(content || ""), opts),
         :ok <- chown(path, file.owner, file.group, opts) do
      chmod(path, file.mode, opts)
    end
  end

  defp apply_user(%User{name: name} = user, opts) do
    args = if user.system, do: ["--system"], else: []
    args = if user.home, do: args ++ ["--home", user.home], else: args
    args = if user.shell, do: args ++ ["--shell", user.shell], else: args
    args = args ++ Enum.flat_map(user.groups, &["--groups", &1])

    cmd(opts, "useradd", args ++ [name])
  end

  defp apply_systemd_unit(name, content, opts) do
    path = Path.join(Keyword.get(opts, :systemd_unit_dir, "/etc/systemd/system"), name)
    owner = Keyword.get(opts, :systemd_unit_owner, "root")
    group = Keyword.get(opts, :systemd_unit_group, "root")

    with :ok <- mkdir_p(Path.dirname(path), opts),
         :ok <- write_file(path, IO.iodata_to_binary(content), opts),
         :ok <- chown(path, owner, group, opts) do
      chmod(path, 0o644, opts)
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
      cmd(opts, "systemctl", ["daemon-reload"])
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

  defp chown(_path, nil, nil, _opts), do: :ok

  defp chown(path, owner, group, opts) do
    spec = [owner || "", group || ""] |> Enum.join(":") |> String.trim_trailing(":")
    cmd(opts, "chown", [spec, path])
  end

  defp chmod(_path, nil, _opts), do: :ok

  defp chmod(path, mode, opts) do
    cmd(opts, "chmod", [Integer.to_string(mode, 8), path])
  end

  defp cmd(opts, command, args) do
    {command, args} = maybe_sudo(command, args, opts)

    case Runner.cmd(runner(opts), command, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:command_failed, command, args, status, output}}
    end
  end

  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)

  defp maybe_sudo(command, args, opts) do
    if Keyword.get(opts, :sudo, false), do: {"sudo", [command | args]}, else: {command, args}
  end

  defp skipped(change), do: %{change: change, status: :skipped}
end
