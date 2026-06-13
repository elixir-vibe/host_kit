defmodule HostKit.DSL.EnvFile.Scope do
  @moduledoc false

  @key {__MODULE__, :env_file}

  def start(path, opts) do
    Process.put(@key, %HostKit.Resources.EnvFile{
      path: path,
      owner: Keyword.get(opts, :owner),
      group: Keyword.get(opts, :group),
      mode: Keyword.get(opts, :mode, 0o640)
    })
  end

  def finish do
    Process.delete(@key) || raise "no HostKit env_file in scope"
  end

  def active?, do: Process.get(@key) != nil

  def put_set(key, value) do
    update(&%{&1 | entries: &1.entries ++ [{:set, normalize_key(key), to_string(value)}]})
  end

  def put_secret(key, opts) do
    source =
      if env = Keyword.get(opts, :env) do
        {:env, env}
      else
        raise ArgumentError, "secret requires :env source"
      end

    update(&%{&1 | entries: &1.entries ++ [{:secret, normalize_key(key), source}]})
  end

  defp update(fun) do
    env_file = Process.get(@key) || raise "no HostKit env_file in scope"
    Process.put(@key, fun.(env_file))
    :ok
  end

  defp normalize_key(key) when is_atom(key), do: key |> Atom.to_string() |> String.upcase()
  defp normalize_key(key), do: to_string(key)
end
