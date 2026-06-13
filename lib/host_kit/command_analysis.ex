defmodule HostKit.CommandAnalysis do
  @moduledoc "Static command dependency analysis for HostKit resources."

  alias HostKit.{Diagnostic, Diagnostics, Resource}
  alias HostKit.Resources.{Command, Mise, Package, Shell}

  @baseline_commands MapSet.new(
                       ~w[base64 bash cd echo export false install mkdir printf pwd rm set sh sudo systemctl test true]
                     )

  @spec validate([struct()]) :: :ok | {:error, Diagnostics.t()}
  def validate(resources) do
    provided = provided_commands(resources)

    diagnostics =
      resources
      |> Enum.flat_map(&required_command_diagnostics(&1, provided))
      |> Diagnostics.new()

    if Diagnostics.ok?(diagnostics), do: :ok, else: {:error, diagnostics}
  end

  @spec provided_commands([struct()]) :: MapSet.t(String.t())
  def provided_commands(resources) do
    resources
    |> Enum.flat_map(&provided_by/1)
    |> Kernel.++(MapSet.to_list(@baseline_commands))
    |> MapSet.new()
  end

  @spec required_commands(struct()) :: [String.t()]
  def required_commands(resource), do: Enum.map(required_command_refs(resource), & &1.name)

  def required_command_refs(%Command{exec: {command, _args}, runtime: {:mise, _name}}),
    do: [%{name: command}]

  def required_command_refs(%Command{exec: {command, _args}}), do: [%{name: command}]

  def required_command_refs(%Shell{script: %HostKit.ShellScript{commands: commands}}),
    do: commands

  def required_command_refs(_resource), do: []

  defp required_command_diagnostics(resource, provided) do
    resource
    |> required_command_refs()
    |> Enum.reject(&MapSet.member?(provided, &1.name))
    |> Enum.map(&missing_command(resource, &1))
  end

  defp missing_command(resource, %{name: command} = command_ref) do
    %Diagnostic{
      severity: :error,
      code: :missing_command_provider,
      message: ~s(command "#{command}" is required but not provided),
      resource_id: Resource.id(resource),
      file: get_in(resource.meta, [:source, :file]),
      line: get_in(resource.meta, [:source, :line]),
      column: get_in(resource.meta, [:source, :column]),
      details: %{
        command: command,
        required_by: Resource.id(resource),
        shell_line: Map.get(command_ref, :line),
        shell_column: Map.get(command_ref, :column)
      },
      hint:
        "Add `package :#{String.replace(command, "-", "_")}` or a resource with `provides: [\"#{command}\"]`."
    }
  end

  defp provided_by(%Package{} = package) do
    case Map.get(package.meta, :provides) do
      nil -> [package.system_name]
      values -> Enum.map(values, &to_string/1)
    end
  end

  defp provided_by(%Mise{} = mise) do
    Enum.flat_map(mise.tools, &provided_by_tool/1)
  end

  defp provided_by(_resource), do: []

  defp provided_by_tool(%{name: name}) when name in [:elixir, "elixir"],
    do: ["elixir", "iex", "mix"]

  defp provided_by_tool(%{name: name}) when name in [:erlang, "erlang"], do: ["erl", "erlc"]
  defp provided_by_tool(%{name: name}), do: [to_string(name)]
end
