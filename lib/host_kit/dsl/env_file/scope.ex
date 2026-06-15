defmodule HostKit.DSL.EnvFile.Scope do
  @moduledoc false

  @key {__MODULE__, :env_file}

  def start(path, opts) do
    Process.put(
      @key,
      HostKit.Resources.EnvFile.new(path, Keyword.put_new(opts, :mode, :secret_group_file))
    )
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
      case Keyword.fetch(opts, :env) do
        {:ok, :redacted} ->
          :redacted

        {:ok, env} when is_binary(env) ->
          HostKit.Secret.env(env)

        {:ok, env} ->
          raise ArgumentError, "secret :env expects a string or :redacted, got: #{inspect(env)}"

        :error ->
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
