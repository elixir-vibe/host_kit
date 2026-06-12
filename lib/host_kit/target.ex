defmodule HostKit.Target do
  @moduledoc "Execution target for HostKit read/apply operations."

  @type t :: %__MODULE__{
          name: atom(),
          runner: module() | {module(), keyword()},
          opts: keyword()
        }

  defstruct name: nil,
            runner: HostKit.Runner.Local,
            opts: []

  @spec local(atom(), keyword()) :: t()
  def local(name, opts \\ []) when is_atom(name) do
    {runner, opts} = Keyword.pop(opts, :runner, HostKit.Runner.Local)
    %__MODULE__{name: name, runner: runner, opts: opts}
  end

  @spec ssh(atom(), keyword()) :: t()
  def ssh(name, opts) when is_atom(name) do
    {runner, opts} = Keyword.pop(opts, :runner, HostKit.Runner.SSH)
    %__MODULE__{name: name, runner: runner, opts: opts}
  end

  @spec opts(t(), keyword()) :: keyword()
  def opts(%__MODULE__{} = target, extra \\ []) do
    target.opts
    |> Keyword.put(:runner, runner(target))
    |> Keyword.merge(extra)
  end

  defp runner(%__MODULE__{runner: {module, runner_opts}, opts: opts}) do
    {module, Keyword.merge(opts, runner_opts)}
  end

  defp runner(%__MODULE__{runner: module, opts: opts}) when is_atom(module), do: {module, opts}
end
