defmodule HostKit.DSL.ConfigFile.Scope do
  @moduledoc false

  @key {__MODULE__, :config}
  @section_key {__MODULE__, :section}

  def start(path, format, opts) do
    Process.put(@key, %{path: path, format: format, opts: opts, content: %{}})
  end

  def finish do
    %{path: path, format: format, opts: opts, content: content} =
      Process.delete(@key) || raise "no HostKit config file in scope"

    HostKit.Resources.ConfigFile.new(path, format, Keyword.put(opts, :content, content))
  end

  def active?, do: match?(%{}, Process.get(@key))

  def start_section(name) do
    active?() || raise "section/2 used outside ini/2 block"
    Process.put(@section_key, name)
  end

  def finish_section do
    Process.delete(@section_key) || raise "section/2 used outside ini/2 block"
    :ok
  end

  def put_set(key, value), do: put_value(:set, key, value)

  def put_secret(key, opts) do
    value =
      case Keyword.fetch!(opts, :env) do
        :redacted -> :redacted
        env when is_binary(env) -> HostKit.Secret.env(env)
      end

    put_value(:secret, key, value)
  end

  defp put_value(_kind, key, value) do
    config = Process.get(@key) || raise "set/2 used outside HostKit config file scope"

    content =
      case Process.get(@section_key) do
        nil ->
          Map.put(config.content, key, value)

        section ->
          Map.update(config.content, section, %{key => value}, fn values ->
            Map.put(values, key, value)
          end)
      end

    Process.put(@key, %{config | content: content})
  end
end
