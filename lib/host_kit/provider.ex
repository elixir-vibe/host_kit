defmodule HostKit.Provider do
  @moduledoc """
  Provider behaviour for HostKit integrations.

  Providers own resource types, schemas, planning, applying, and optional DSL
  modules. This follows Terraform's provider/resource split while staying
  Elixir-native.
  """

  @callback provider_name() :: atom()
  @callback dsl_modules() :: [module()]
  @callback resource_types() :: [atom()]
  @callback read(resource :: struct(), context :: map()) ::
              {:ok, struct() | nil} | :ignore | {:error, term()}
  @callback plan(resource :: struct(), actual :: struct() | nil, context :: map()) ::
              {:ok, [HostKit.Change.t()]} | :ignore | {:error, term()}
  @callback apply(change :: HostKit.Change.t(), context :: map()) ::
              :ok | :ignore | {:error, term()}
  @callback render(resource :: struct(), context :: map()) ::
              {:ok, iodata()} | :ignore | {:error, term()}
  @callback validate(resource :: struct(), context :: map()) :: :ok | :ignore | {:error, term()}

  @optional_callbacks dsl_modules: 0,
                      resource_types: 0,
                      read: 2,
                      plan: 3,
                      apply: 2,
                      render: 2,
                      validate: 2

  @spec resolve([module()] | keyword()) :: [module()]
  def resolve(opts_or_providers \\ [])

  def resolve(opts) when is_list(opts) do
    opts
    |> Keyword.get(:providers, Keyword.get(opts, :plugins, opts))
    |> Enum.uniq()
  end

  @spec dsl_modules([module()]) :: [module()]
  def dsl_modules(providers) do
    providers
    |> Enum.flat_map(fn provider ->
      if exports?(provider, :dsl_modules, 0), do: provider.dsl_modules(), else: []
    end)
    |> Enum.uniq()
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

  defp render_with(provider, resource, context) do
    if exports?(provider, :render, 2) do
      case provider.render(resource, context) do
        :ignore -> nil
        result -> result
      end
    end
  end

  defp validate_with(provider, resource, context) do
    if exports?(provider, :validate, 2) do
      case provider.validate(resource, context) do
        :ok -> []
        :ignore -> []
        {:error, reason} -> [{provider, reason}]
      end
    else
      []
    end
  end

  defp exports?(provider, function, arity) do
    Code.ensure_loaded?(provider) and function_exported?(provider, function, arity)
  end
end
