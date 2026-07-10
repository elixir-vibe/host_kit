defmodule HostKit.Provider do
  @moduledoc """
  Provider behaviour for HostKit integrations.

  Providers contribute resource types, validation, rendering, apply behavior,
  and optional DSL modules. Provider DSLs should prefer compiling to ordinary
  HostKit resources whenever core planning and apply behavior is sufficient.
  """

  @callback provider_name() :: atom()
  @callback dsl_modules() :: [module()]
  @callback resource_types() :: [module()]
  @callback read(resource :: struct(), context :: map()) ::
              {:ok, struct() | nil} | :ignore | {:error, term()}
  @callback apply(change :: HostKit.Change.t(), context :: map()) ::
              :ok | :ignore | {:error, term()}
  @callback render(resource :: struct(), context :: map()) ::
              {:ok, iodata()} | :ignore | {:error, term()}
  @callback validate(resource :: struct(), context :: map()) :: :ok | :ignore | {:error, term()}

  @optional_callbacks dsl_modules: 0,
                      resource_types: 0,
                      read: 2,
                      apply: 2,
                      render: 2,
                      validate: 2

  @spec resolve([module()] | keyword()) :: [module()]
  def resolve(opts_or_providers \\ [])

  def resolve(opts) when is_list(opts) do
    providers =
      if Keyword.keyword?(opts) do
        Keyword.get(opts, :providers, [])
      else
        opts
      end

    Enum.uniq(providers)
  end

  @spec dsl_modules([module()]) :: [module()]
  def dsl_modules(providers) do
    providers
    |> Enum.flat_map(fn provider ->
      if exports?(provider, :dsl_modules, 0), do: provider.dsl_modules(), else: []
    end)
    |> Enum.uniq()
  end

  @spec read([module()], struct(), map()) ::
          {:ok, struct() | nil} | :ignore | {:error, term()}
  def read(providers, resource, context \\ %{}) do
    Enum.find_value(providers, :ignore, &read_with(&1, resource, context))
  end

  @spec apply([module()], HostKit.Change.t(), map()) :: :ok | {:error, term()}
  def apply(providers, change, context \\ %{}) do
    Enum.find_value(providers, {:error, :no_applier}, &apply_with(&1, change, context))
  end

  @spec render([module()], struct(), map()) :: {:ok, iodata()} | {:error, term()}
  def render(providers, resource, context \\ %{}) do
    Enum.find_value(providers, {:error, :no_renderer}, &render_with(&1, resource, context))
  end

  @spec validate([module()], struct(), map()) :: :ok | {:error, [term()]}
  def validate(providers, resource, context \\ %{}) do
    errors = Enum.flat_map(providers, &validate_with(&1, resource, context))

    if errors == [], do: :ok, else: {:error, errors}
  end

  defp read_with(provider, resource, context) do
    if supports?(provider, resource) and exports?(provider, :read, 2) do
      case provider.read(resource, context) do
        :ignore -> nil
        result -> result
      end
    end
  end

  defp apply_with(provider, change, context) do
    resource = change.after || change.before

    if supports?(provider, resource) and exports?(provider, :apply, 2) do
      case provider.apply(change, context) do
        :ignore -> nil
        result -> result
      end
    end
  end

  defp render_with(provider, resource, context) do
    if supports?(provider, resource) and exports?(provider, :render, 2) do
      case provider.render(resource, context) do
        :ignore -> nil
        result -> result
      end
    end
  end

  defp validate_with(provider, resource, context) do
    if supports?(provider, resource) and exports?(provider, :validate, 2) do
      case provider.validate(resource, context) do
        :ok -> []
        :ignore -> []
        {:error, reason} -> [{provider, reason}]
      end
    else
      []
    end
  end

  defp supports?(provider, %module{}) do
    not exports?(provider, :resource_types, 0) or module in provider.resource_types()
  end

  defp supports?(_provider, _resource), do: false

  defp exports?(provider, function, arity) do
    Code.ensure_loaded?(provider) and function_exported?(provider, function, arity)
  end
end
