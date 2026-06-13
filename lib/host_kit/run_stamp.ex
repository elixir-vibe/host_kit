defmodule HostKit.RunStamp do
  @moduledoc "Reproducibility stamps for command-like resources."

  alias HostKit.Resources.{Command, Shell}
  alias HostKit.Runner

  @stamp_dir "/var/lib/hostkit/stamps"

  def stamp_path(%Command{} = resource),
    do: resource.stamp || default_stamp_path(:command, resource.name)

  def stamp_path(%Shell{} = resource),
    do: resource.stamp || default_stamp_path(:shell, resource.name)

  def stamp_required?(%{stamp: stamp}) when is_binary(stamp), do: true
  def stamp_required?(%{inputs: [_ | _]}), do: true
  def stamp_required?(%{outputs: [_ | _]}), do: true
  def stamp_required?(_resource), do: false

  def desired(%Command{} = resource, opts) do
    base_stamp(resource, opts)
    |> Map.put("kind", "command")
    |> Map.put("exec", Tuple.to_list(resource.exec))
    |> Map.put("runtime", dump_runtime(resource.runtime))
  end

  def desired(%Shell{} = resource, opts) do
    base_stamp(resource, opts)
    |> Map.put("kind", "shell")
    |> Map.put("script_sha256", sha256(resource.script.source))
    |> Map.put("commands", Enum.map(resource.script.commands, & &1.name))
  end

  def current?(resource, opts) do
    cond do
      resource.creates && not exists?(resource.creates, resource.cwd, opts) ->
        false

      resource.outputs != [] && not Enum.all?(resource.outputs, &exists?(&1, resource.cwd, opts)) ->
        false

      stamp_required?(resource) ->
        stamp_matches?(resource, opts)

      resource.creates ->
        true

      true ->
        false
    end
  end

  def write(resource, opts) do
    if stamp_required?(resource) do
      path = stamp_path(resource)
      content = Jason.encode!(desired(resource, opts), pretty: true)

      with :ok <- Runner.mkdir_p(runner(opts), Path.dirname(path), opts) do
        Runner.write_file(runner(opts), path, content, opts)
      end
    else
      :ok
    end
  end

  def read(resource, opts) do
    path = stamp_path(resource)

    case Runner.cmd(runner(opts), "sh", ["-c", "base64 #{HostKit.Shell.escape(path)}"],
           stderr_to_stdout: true
         ) do
      {content, 0} ->
        content
        |> String.replace(~r/\s+/, "")
        |> Base.decode64()
        |> case do
          {:ok, json} -> Jason.decode(json)
          :error -> {:error, :invalid_base64_stamp}
        end

      {_output, _status} ->
        {:error, :missing_stamp}
    end
  end

  def exists?(path, opts), do: exists?(path, nil, opts)

  def exists?(path, nil, opts),
    do: match?(:ok, HostKit.Runner.Ops.cmd(opts, "test", ["-e", path]))

  def exists?(path, cwd, opts) do
    script = "cd #{HostKit.Shell.escape(cwd)} && test -e #{HostKit.Shell.escape(path)}"
    match?(:ok, HostKit.Runner.Ops.cmd(opts, "sh", ["-c", script]))
  end

  defp stamp_matches?(resource, opts) do
    case read(resource, opts) do
      {:ok, current} -> current == desired(resource, opts)
      {:error, _reason} -> false
    end
  end

  defp base_stamp(resource, opts) do
    %{
      "version" => 1,
      "resource_id" => inspect(HostKit.Resource.id(resource)),
      "cwd" => resource.cwd,
      "env" => resource.env,
      "creates" => resource.creates,
      "inputs" => dump_inputs(path_inputs(resource.inputs)),
      "source_inputs" => source_inputs(resource.inputs, opts),
      "outputs" => resource.outputs,
      "input_digest" => input_digest(resource, opts)
    }
  end

  defp input_digest(%{inputs: []}, _opts), do: nil

  defp input_digest(%{inputs: inputs, cwd: cwd}, opts) do
    inputs = path_inputs(inputs)

    if inputs == [] do
      nil
    else
      script = input_digest_script(inputs, cwd)

      case Runner.cmd(runner(opts), "sh", ["-c", script], stderr_to_stdout: true) do
        {digest, 0} -> String.trim(digest)
        {_output, _status} -> :missing_or_unreadable_inputs
      end
    end
  end

  defp input_digest_script(inputs, nil), do: digest_pipeline(inputs)

  defp input_digest_script(inputs, cwd),
    do: "cd #{HostKit.Shell.escape(cwd)} && #{digest_pipeline(inputs)}"

  defp digest_pipeline(inputs) do
    patterns = Enum.map_join(inputs, " ", &HostKit.Shell.escape/1)

    "find #{patterns} -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}'"
  end

  defp path_inputs(inputs), do: Enum.filter(inputs, &is_binary/1)

  defp dump_inputs(inputs), do: inputs

  defp source_inputs(inputs, opts) do
    inputs
    |> Enum.filter(&source_input?/1)
    |> Map.new(fn %HostKit.Source.Ref{name: name} ->
      {to_string(name), name |> source_identity(opts) |> HostKit.Source.Identity.dump()}
    end)
  end

  defp source_input?(%HostKit.Source.Ref{}), do: true
  defp source_input?(_input), do: false

  defp source_identity(name, opts) do
    opts
    |> Keyword.get(:resources, [])
    |> Enum.find(&match?(%HostKit.Resources.Source{name: ^name}, &1))
    |> case do
      %HostKit.Resources.Source{} = source -> current_or_desired_source_identity(source, opts)
      nil -> %HostKit.Source.Identity{type: :missing, ref_kind: :unknown, path: "."}
    end
  end

  defp current_or_desired_source_identity(source, opts) do
    case HostKit.Source.Git.read(source, opts) do
      {:ok, %HostKit.Resources.Source{revision: revision} = actual}
      when revision == source.revision ->
        HostKit.Resources.Source.identity(actual)

      _other ->
        HostKit.Resources.Source.identity(source)
    end
  end

  defp dump_runtime(nil), do: nil
  defp dump_runtime({kind, name}), do: [to_string(kind), to_string(name)]

  defp default_stamp_path(type, name) do
    Path.join(@stamp_dir, "#{type}-#{safe_name(name)}.json")
  end

  defp safe_name(name) do
    name
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_.-]+/, "-")
    |> String.trim("-.")
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp runner(opts), do: Keyword.get(opts, :runner, HostKit.Runner.Local)
end
