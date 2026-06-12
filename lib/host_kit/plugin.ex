defmodule HostKit.Plugin do
  @moduledoc "Plugin behaviour and dispatch helpers."

  @callback dsl_modules() :: [module()]
  @callback resource_types() :: [module()]
  @callback render(resource :: struct(), context :: map()) ::
              {:ok, iodata()} | :ignore | {:error, term()}
  @callback validate(resource :: struct(), context :: map()) :: :ok | :ignore | {:error, term()}
  @callback inference_hints() :: %{optional(:deps) => [atom()], optional(:source) => [String.t()]}

  @optional_callbacks dsl_modules: 0,
                      resource_types: 0,
                      render: 2,
                      validate: 2,
                      inference_hints: 0

  @built_in_plugins [
    HostKit.Plugins.Systemd,
    HostKit.Plugins.Unitctl
  ]

  @doc "Returns first-party core plugins."
  @spec built_in_plugins() :: [module()]
  def built_in_plugins, do: @built_in_plugins

  @doc "Resolves plugins from explicit modules plus first-party built-ins."
  @spec resolve([module()] | keyword()) :: [module()]
  def resolve(opts_or_plugins \\ [])

  def resolve(opts) when is_list(opts) do
    plugins = Keyword.get(opts, :plugins, opts)
    Enum.uniq(@built_in_plugins ++ plugins)
  end

  @spec dsl_modules([module()]) :: [module()]
  def dsl_modules(plugins) do
    plugins
    |> Enum.flat_map(fn plugin ->
      if exports?(plugin, :dsl_modules, 0), do: plugin.dsl_modules(), else: []
    end)
    |> Enum.uniq()
  end

  @spec render([module()], struct(), map()) :: {:ok, iodata()} | {:error, term()}
  def render(plugins, resource, context \\ %{}) do
    Enum.find_value(plugins, {:error, :no_renderer}, fn plugin ->
      if exports?(plugin, :render, 2) do
        case plugin.render(resource, context) do
          :ignore -> nil
          result -> result
        end
      end
    end)
  end

  @spec validate([module()], struct(), map()) :: :ok | {:error, [term()]}
  def validate(plugins, resource, context \\ %{}) do
    errors =
      Enum.flat_map(plugins, fn plugin ->
        if exports?(plugin, :validate, 2) do
          case plugin.validate(resource, context) do
            :ok -> []
            :ignore -> []
            {:error, reason} -> [{plugin, reason}]
          end
        else
          []
        end
      end)

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp exports?(plugin, function, arity) do
    Code.ensure_loaded?(plugin) and function_exported?(plugin, function, arity)
  end
end
