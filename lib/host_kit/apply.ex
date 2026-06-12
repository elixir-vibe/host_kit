defmodule HostKit.Apply do
  @moduledoc "Applies supported HostKit plan changes."

  alias HostKit.{Change, Plan}
  alias HostKit.Resources.{Directory, File}

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
    Enum.reduce_while(changes, {:ok, []}, fn change, {:ok, results} ->
      case apply_change(change, opts) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        {:error, reason} -> {:halt, {:error, {change.resource_id, reason}}}
      end
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end)
  end

  defp apply_change(%Change{action: :no_op} = change, _opts), do: {:ok, skipped(change)}
  defp apply_change(%Change{action: :read} = change, _opts), do: {:ok, skipped(change)}
  defp apply_change(%Change{action: :delete}, _opts), do: {:error, :delete_not_supported}

  defp apply_change(%Change{action: action, after: %Directory{} = directory} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_directory(directory, opts) end)
  end

  defp apply_change(%Change{action: action, after: %File{} = file} = change, opts)
       when action in [:create, :update] do
    apply_or_dry_run(change, opts, fn -> apply_file(file, opts) end)
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
    with :ok <- Elixir.File.mkdir_p(path),
         :ok <- chown(path, directory.owner, directory.group, opts) do
      chmod(path, directory.mode, opts)
    end
  end

  defp apply_file(%File{content: content}, _opts) when content in [:redacted, :managed_elsewhere],
    do: {:error, :file_content_managed_elsewhere}

  defp apply_file(%File{path: path, content: content} = file, opts) do
    with :ok <- Elixir.File.mkdir_p(Path.dirname(path)),
         :ok <- Elixir.File.write(path, IO.iodata_to_binary(content || "")),
         :ok <- chown(path, file.owner, file.group, opts) do
      chmod(path, file.mode, opts)
    end
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

    case System.cmd(command, args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:command_failed, command, args, status, output}}
    end
  end

  defp maybe_sudo(command, args, opts) do
    if Keyword.get(opts, :sudo, false), do: {"sudo", [command | args]}, else: {command, args}
  end

  defp skipped(change), do: %{change: change, status: :skipped}
end
