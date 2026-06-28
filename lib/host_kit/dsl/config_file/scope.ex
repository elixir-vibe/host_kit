defmodule HostKit.DSL.ConfigFile.Scope do
  @moduledoc false

  alias HostKit.DSLCore

  @key {__MODULE__, :config}
  @section_key {__MODULE__, :section}

  def start(path, format, opts) do
    DSLCore.start(@key, :config_file, %{path: path, format: format, opts: opts, content: %{}})
  end

  def finish do
    %{path: path, format: format, opts: opts, content: content} =
      DSLCore.finish(@key, :config_file)

    HostKit.Resources.ConfigFile.new(path, format, Keyword.put(opts, :content, content))
  end

  def active?, do: DSLCore.active?(@key)

  def start_section(name) do
    active?() || raise ArgumentError, "section/2 used outside ini/2 block"
    DSLCore.start(@section_key, :section, name)
  end

  def finish_section do
    DSLCore.finish(@section_key, :section)
    :ok
  end

  def put_set(key, value), do: put_value(:set, key, value)

  def put_secret(key, opts) do
    put_value(:secret, key, HostKit.Secret.from_opts!(opts))
  end

  defp put_value(_kind, key, value) do
    DSLCore.update(@key, fn config ->
      content =
        if DSLCore.active?(@section_key) do
          section = DSLCore.current!(@section_key)

          Map.update(config.content, section, %{key => value}, fn values ->
            Map.put(values, key, value)
          end)
        else
          Map.put(config.content, key, value)
        end

      %{config | content: content}
    end)
  end
end
