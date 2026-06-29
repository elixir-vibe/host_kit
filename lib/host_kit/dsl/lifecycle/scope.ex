defmodule HostKit.DSL.Lifecycle.Scope do
  @moduledoc "Process-local scope helpers for HostKit lifecycle command DSL blocks."

  use DSL

  defmodule Command do
    @moduledoc "State accumulated while evaluating a lifecycle command DSL block."

    @enforce_keys [:name, :phase, :opts]
    defstruct name: nil,
              phase: nil,
              opts: [],
              exec: nil

    @type t :: %__MODULE__{
            name: atom(),
            phase: atom(),
            opts: keyword(),
            exec: term()
          }
  end

  defmodule Context do
    @moduledoc "State accumulated while collecting lifecycle commands for a higher-level DSL."

    @enforce_keys [:ref]
    defstruct ref: nil,
              commands: [],
              collect?: false,
              name: nil,
              eval: nil,
              depends_on: nil,
              cwd: nil,
              env: nil,
              timeout: nil,
              down: nil,
              inputs: nil,
              outputs: nil,
              stamp: nil

    @type t :: %__MODULE__{
            ref: reference(),
            commands: [HostKit.Resources.Command.t()],
            collect?: boolean(),
            name: (atom() -> atom()) | nil,
            eval: (String.t(), keyword() -> term()) | nil,
            depends_on: term(),
            cwd: term(),
            env: term(),
            timeout: term(),
            down: term(),
            inputs: term(),
            outputs: term(),
            stamp: term()
          }
  end

  scope(:lifecycle_command)
  scope(:lifecycle_context)

  def start(name, phase, opts) do
    push_lifecycle_command(%Command{name: name, phase: phase, opts: opts})
  end

  def active?, do: lifecycle_command_active?()

  def put_exec(exec) do
    if active?() do
      update_lifecycle_command(&%{&1 | exec: exec})
      :ok
    else
      raise "lifecycle command used outside lifecycle block"
    end
  end

  def finish do
    scope =
      if active?() do
        pop_lifecycle_command()
      else
        raise "no HostKit lifecycle command in scope"
      end

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
    context = struct!(Context, Map.put(attrs, :ref, make_ref()))
    push_lifecycle_context(context)
    context
  end

  def finish_context(%Context{ref: ref}) do
    if lifecycle_context_active?() and current_lifecycle_context!().ref == ref do
      pop_lifecycle_context().commands
    else
      raise "HostKit lifecycle context stack mismatch"
    end
  end

  defp collect(command) do
    if lifecycle_context_active?() do
      update_lifecycle_context(&%{&1 | commands: &1.commands ++ [command]})
      :ok
    else
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
      {:ok, nil} -> opts
      {:ok, value} -> Keyword.put_new(opts, key, value)
      :error -> opts
    end
  end

  defp current_context, do: current_lifecycle_context() || %{}
end
