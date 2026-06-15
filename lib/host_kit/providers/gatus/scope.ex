defmodule HostKit.Providers.Gatus.Scope do
  @moduledoc false

  @config_key {__MODULE__, :config}
  @telegram_key {__MODULE__, :telegram_alerting}

  def start_config(path, opts) do
    Process.put(@config_key, %{path: path, opts: opts, content: []})
  end

  def put_web(opts) do
    update_config(&put_content(&1, :web, normalize_keyword(opts)))
  end

  def put_storage(type, opts) do
    storage = [type: to_string(type)] ++ normalize_keyword(opts)
    update_config(&put_content(&1, :storage, storage))
  end

  def start_telegram_alerting(opts) do
    Process.put(@telegram_key, normalize_keyword(opts))
  end

  def put_default_alert(opts) do
    update_telegram(fn telegram ->
      put_keyword(telegram, :"default-alert", normalize_keyword(opts))
    end)
  end

  def finish_telegram_alerting do
    telegram = Process.delete(@telegram_key) || raise "no gatus telegram alerting in scope"

    update_config(fn config ->
      put_content(config, :alerting, telegram: telegram)
    end)
  end

  def add_endpoint(name, opts) do
    endpoint =
      opts
      |> normalize_keyword()
      |> then(&([name: name] ++ &1))
      |> normalize_endpoint_alerts()

    add_endpoint_config(endpoint)
  end

  def add_endpoints(endpoints) when is_list(endpoints) do
    Enum.each(endpoints, &add_endpoint_config/1)
  end

  def add_monitor_endpoints(opts) do
    HostKit.DSL.Scope.current_project()
    |> HostKit.Providers.Gatus.endpoints_from_monitors(opts)
    |> add_endpoints()
  end

  def finish_config do
    %{path: path, opts: opts, content: content} =
      Process.delete(@config_key) || raise "no gatus config in scope"

    HostKit.Resources.ConfigFile.new(path, :yaml, Keyword.put(opts, :content, content))
  end

  defp add_endpoint_config(endpoint) do
    endpoint = endpoint |> normalize_keyword() |> normalize_endpoint_alerts()

    update_config(fn config ->
      update_content(config, :endpoints, fn endpoints -> List.wrap(endpoints) ++ [endpoint] end)
    end)
  end

  defp update_config(fun) do
    config = Process.get(@config_key) || raise "no gatus config in scope"
    Process.put(@config_key, fun.(config))
    :ok
  end

  defp update_telegram(fun) do
    telegram = Process.get(@telegram_key) || raise "no gatus telegram alerting in scope"
    Process.put(@telegram_key, fun.(telegram))
    :ok
  end

  defp put_content(config, key, value) do
    update_content(config, key, fn _current -> value end)
  end

  defp update_content(%{content: content} = config, key, fun) do
    current = Keyword.get(content, key)
    content = put_keyword(content, key, fun.(current))
    %{config | content: content}
  end

  defp put_keyword(keyword, key, value) do
    if Keyword.has_key?(keyword, key) do
      Keyword.replace!(keyword, key, value)
    else
      keyword ++ [{key, value}]
    end
  end

  defp normalize_keyword(opts) when is_list(opts), do: opts
  defp normalize_keyword(opts) when is_map(opts), do: Map.to_list(opts)

  defp normalize_endpoint_alerts(endpoint) do
    Keyword.update(endpoint, :alerts, [], fn alerts ->
      Enum.map(List.wrap(alerts), fn
        type when is_atom(type) -> [type: to_string(type)]
        type when is_binary(type) -> [type: type]
        alert when is_list(alert) -> alert
      end)
    end)
  end
end
