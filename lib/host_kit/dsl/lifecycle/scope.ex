defmodule HostKit.DSL.Lifecycle.Scope do
  @moduledoc false

  @scope_key {__MODULE__, :scope}
  @context_key {__MODULE__, :context}

  def start(name, phase, opts) do
    Process.put(@scope_key, %{name: name, phase: phase, opts: opts, exec: nil})
    :ok
  end

  def active?, do: Process.get(@scope_key) != nil

  def put_exec(exec) do
    scope = Process.get(@scope_key) || raise "lifecycle command used outside lifecycle block"
    Process.put(@scope_key, %{scope | exec: exec})
    :ok
  end

  def finish do
    scope = Process.delete(@scope_key) || raise "no HostKit lifecycle command in scope"

    exec =
      scope.exec || raise "lifecycle command #{inspect(scope.name)} did not declare an executable"

    context = current_context()

    command =
      scope.name
      |> command_name(context)
      |> HostKit.Resources.Command.new(
        scope.opts
        |> Keyword.put(:exec, exec)
        |> Keyword.put_new(:phase, scope.phase)
        |> put_context_defaults(context)
      )

    case context do
      %{collect?: true} -> collect(command)
      _context -> HostKit.DSL.Scope.add_resource(command)
    end
  end

  def eval_exec(expression, opts) do
    case current_context() do
      %{eval: eval} when is_function(eval, 2) -> eval.(expression, opts)
      _context -> HostKit.CommandLine.eval(expression, opts)
    end
  end

  def start_context(attrs) when is_map(attrs) do
    context = attrs |> Map.put_new(:commands, []) |> Map.put(:ref, make_ref())
    Process.put(@context_key, [context | context_stack()])
    context
  end

  def finish_context(%{ref: ref}) do
    case context_stack() do
      [%{ref: ^ref} = context | rest] ->
        Process.put(@context_key, rest)
        context.commands

      _other ->
        raise "HostKit lifecycle context stack mismatch"
    end
  end

  defp collect(command) do
    case context_stack() do
      [context | rest] ->
        Process.put(@context_key, [%{context | commands: context.commands ++ [command]} | rest])
        :ok

      [] ->
        raise "no HostKit lifecycle context in scope"
    end
  end

  defp command_name(name, %{name: fun}) when is_function(fun, 1), do: fun.(name)
  defp command_name(name, _context), do: name

  defp put_context_defaults(opts, context) do
    opts
    |> put_new_from_context(:depends_on, context)
    |> put_new_from_context(:cwd, context)
    |> put_new_from_context(:env, context)
    |> put_new_from_context(:timeout, context)
    |> put_new_from_context(:down, context)
    |> put_new_from_context(:inputs, context)
    |> put_new_from_context(:outputs, context)
    |> put_new_from_context(:stamp, context)
  end

  defp put_new_from_context(opts, key, context) do
    case Map.fetch(context, key) do
      {:ok, value} -> Keyword.put_new(opts, key, value)
      :error -> opts
    end
  end

  defp current_context, do: List.first(context_stack(), %{})
  defp context_stack, do: Process.get(@context_key, [])
end
