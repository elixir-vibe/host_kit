defmodule HostKit.Runner do
  @moduledoc "Command execution boundary for HostKit apply/deploy operations."

  @type command :: String.t()
  @type args :: [String.t()]
  @type opts :: keyword()
  @type result :: {String.t(), non_neg_integer()}

  @callback cmd(command(), args(), opts()) :: result()
  @callback mkdir_p(Path.t(), opts()) :: :ok | {:error, term()}
  @callback write_file(Path.t(), iodata(), opts()) :: :ok | {:error, term()}

  @spec cmd(module() | {module(), keyword()}, command(), args(), opts()) :: result()
  def cmd({runner, runner_opts}, command, args, opts) when is_atom(runner) do
    runner.cmd(command, args, Keyword.merge(runner_opts, opts))
  end

  def cmd(runner, command, args, opts) when is_atom(runner) do
    runner.cmd(command, args, opts)
  end

  @spec mkdir_p(module() | {module(), keyword()}, Path.t(), opts()) :: :ok | {:error, term()}
  def mkdir_p({runner, runner_opts}, path, opts) when is_atom(runner) do
    runner.mkdir_p(path, Keyword.merge(runner_opts, opts))
  end

  def mkdir_p(runner, path, opts) when is_atom(runner) do
    runner.mkdir_p(path, opts)
  end

  @spec write_file(module() | {module(), keyword()}, Path.t(), iodata(), opts()) ::
          :ok | {:error, term()}
  def write_file({runner, runner_opts}, path, content, opts) when is_atom(runner) do
    runner.write_file(path, content, Keyword.merge(runner_opts, opts))
  end

  def write_file(runner, path, content, opts) when is_atom(runner) do
    runner.write_file(path, content, opts)
  end
end
