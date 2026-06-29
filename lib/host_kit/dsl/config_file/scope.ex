defmodule HostKit.DSL.ConfigFile.Scope do
  @moduledoc false

  use HostKit.DSLCore

  scope(:config_file)

  scope :section do
    requires(:config_file)
  end

  def start(path, format, opts) do
    push_config_file(%{path: path, format: format, opts: opts, content: %{}})
  end

  def finish do
    %{path: path, format: format, opts: opts, content: content} = pop_config_file()

    HostKit.Resources.ConfigFile.new(path, format, Keyword.put(opts, :content, content))
  end

  def active?, do: config_file_active?()

  def start_section(name) do
    push_section(name)
  end

  def finish_section do
    pop_section()
    :ok
  end

  def put_set(key, value), do: put_value(:set, key, value)

  def put_secret(key, opts) do
    put_value(:secret, key, HostKit.Secret.from_opts!(opts))
  end

  defp put_value(_kind, key, value) do
    update_config_file(fn config ->
      content =
        if section_active?() do
          section = current_section!()

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
