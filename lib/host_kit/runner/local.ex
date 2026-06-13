defmodule HostKit.Runner.Local do
  @moduledoc "Local command runner for HostKit operations."

  @behaviour HostKit.Runner

  @impl true
  def cmd(command, args, opts \\ []) do
    System.cmd(command, args, normalize_opts(opts))
  end

  defp normalize_opts(opts) do
    case Keyword.fetch(opts, :env) do
      {:ok, env} when is_map(env) -> Keyword.put(opts, :env, Map.to_list(env))
      _other -> opts
    end
  end

  @impl true
  def mkdir_p(path, _opts \\ []) do
    Elixir.File.mkdir_p(path)
  end

  @impl true
  def write_file(path, content, _opts \\ []) do
    Elixir.File.write(path, content)
  end
end
