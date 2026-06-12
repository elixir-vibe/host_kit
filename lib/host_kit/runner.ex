defmodule HostKit.Runner do
  @moduledoc "Command execution boundary for HostKit apply/deploy operations."

  @type command :: String.t()
  @type args :: [String.t()]
  @type opts :: keyword()
  @type result :: {String.t(), non_neg_integer()}

  @callback cmd(command(), args(), opts()) :: result()

  @spec cmd(module() | {module(), keyword()}, command(), args(), opts()) :: result()
  def cmd({runner, runner_opts}, command, args, opts) when is_atom(runner) do
    runner.cmd(command, args, Keyword.merge(runner_opts, opts))
  end

  def cmd(runner, command, args, opts) when is_atom(runner) do
    runner.cmd(command, args, opts)
  end
end
