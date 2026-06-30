defmodule HostKit.Providers.Gatus.Scope do
  @moduledoc "Process-local scope helpers for Gatus provider DSL blocks."

  use DSL

  defmodule Config do
    @moduledoc "State accumulated while evaluating a Gatus config block."

    defstruct path: nil, opts: [], content: []
  end

  scope :config do
    accepts(:telegram, into: :content)
    accepts(:telegram_alerting, into: :content)
    accepts(:endpoint, into: :content)
    accepts(:external_endpoint, into: :content)
  end

  scope :telegram do
    requires(:config)
  end

  scope :telegram_alerting do
    requires(:config)
  end

  scope :endpoint do
    requires(:config)
  end

  scope :external_endpoint do
    requires(:config)
  end

  def active?, do: config_active?()

  def start_config(path, opts) do
    push_config(%Config{path: path, opts: opts})
  end

  def put_web(opts) do
    update_config(&put_content(&1, :web, normalize_keyword(opts)))
  end

  def put_storage(type, opts) do
    storage = [type: to_string(type)] ++ normalize_keyword(opts)
    update_config(&put_content(&1, :storage, storage))
  end

  def start_telegram(opts), do: push_telegram(normalize_keyword(opts))

  def put_default_alert(opts) do
    update_telegram_scope(fn telegram ->
      put_keyword(telegram, :"default-alert", normalize_keyword(opts))
    end)
  end

  def finish_telegram do
    telegram = pop_telegram()

    update_config(fn config ->
      put_content(config, :alerting, telegram: telegram)
    end)
  end

  def start_external_endpoint(name, opts) do
    endpoint = opts |> normalize_keyword() |> then(&([name: name] ++ &1))
    push_external_endpoint(endpoint)
  end

  def finish_external_endpoint do
    endpoint = pop_external_endpoint() |> normalize_endpoint_alerts()

    update_config(fn config ->
      update_content(config, :"external-endpoints", fn endpoints ->
        List.wrap(endpoints) ++ [endpoint]
      end)
    end)
  end

  def put_heartbeat(opts) do
    update_endpoint_scope(&put_keyword(&1, :heartbeat, normalize_keyword(opts)))
  end

  def add_condition(condition) do
    update_endpoint_scope(fn endpoint ->
      Keyword.update(endpoint, :conditions, [condition], fn conditions ->
        List.wrap(conditions) ++ [condition]
      end)
    end)
  end

  def add_alert(type, opts \\ []) do
    alert = normalize_alert([type: to_string(type)] ++ normalize_keyword(opts))

    update_endpoint_scope(fn endpoint ->
      Keyword.update(endpoint, :alerts, [alert], fn alerts -> List.wrap(alerts) ++ [alert] end)
    end)
  end

  def add_endpoint(name, opts) do
    endpoint =
      opts |> normalize_keyword() |> then(&([name: name] ++ &1)) |> normalize_endpoint_alerts()

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

  def start_endpoint(name, opts) do
    endpoint = opts |> normalize_keyword() |> then(&([name: name] ++ &1))
    push_endpoint(endpoint)
  end

  def finish_endpoint do
    endpoint = pop_endpoint() |> normalize_endpoint_alerts()
    add_endpoint_config(endpoint)
  end

  def finish_config do
    %Config{path: path, opts: opts, content: content} = pop_config()

    HostKit.Resources.ConfigFile.new(path, :yaml, Keyword.put(opts, :content, content))
  end

  defp add_endpoint_config(endpoint) do
    endpoint = endpoint |> normalize_keyword() |> normalize_endpoint_alerts()

    update_config(fn config ->
      update_content(config, :endpoints, fn endpoints -> List.wrap(endpoints) ++ [endpoint] end)
    end)
  end

  defp update_telegram_scope(fun) do
    cond do
      telegram_active?() -> update_telegram(fun)
      telegram_alerting_active?() -> update_telegram_alerting(fun)
      true -> raise "default_alert must be declared inside telegram/1"
    end
  end

  defp update_endpoint_scope(fun) do
    cond do
      endpoint_active?() -> update_endpoint(fun)
      external_endpoint_active?() -> update_external_endpoint(fun)
      true -> raise "endpoint directive must be declared inside endpoint/2 or external_endpoint/2"
    end
  end

  defp put_content(config, key, value) do
    update_content(config, key, fn _current -> value end)
  end

  defp update_content(%Config{content: content} = config, key, fun) do
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
      Enum.map(List.wrap(alerts), &normalize_alert/1)
    end)
  end

  defp normalize_alert(type) when is_atom(type), do: [type: to_string(type)]
  defp normalize_alert(type) when is_binary(type), do: [type: type]
  defp normalize_alert(alert) when is_map(alert), do: alert |> Map.to_list() |> normalize_alert()
  defp normalize_alert(alert) when is_list(alert), do: alert
end
