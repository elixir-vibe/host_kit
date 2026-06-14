defmodule HostKit.Endpoint do
  @moduledoc "Reference to a named listener/endpoint exposed by a HostKit service."

  @type t :: %__MODULE__{
          service: atom() | String.t(),
          name: atom() | String.t(),
          protocol: atom() | nil,
          host: String.t() | nil,
          port: pos_integer() | nil,
          health: String.t() | nil,
          meta: map()
        }

  defstruct [:service, :name, :protocol, :host, :port, :health, meta: %{}]

  @spec new(atom() | String.t(), atom() | String.t(), keyword()) :: t()
  def new(service, name \\ :default, opts \\ []) do
    %__MODULE__{
      service: service,
      name: name,
      protocol: Keyword.get(opts, :protocol),
      host: Keyword.get(opts, :host),
      port: Keyword.get(opts, :port),
      health: Keyword.get(opts, :health),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec declaration(atom() | String.t(), keyword()) :: t()
  def declaration(name, opts) do
    %__MODULE__{
      name: name,
      protocol: Keyword.get(opts, :protocol, :http),
      host: Keyword.get(opts, :host, "127.0.0.1"),
      port: Keyword.fetch!(opts, :port),
      health: Keyword.get(opts, :health),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec resolved?(t()) :: boolean()
  def resolved?(%__MODULE__{host: host, port: port}), do: is_binary(host) and is_integer(port)

  @spec upstream(t()) :: String.t()
  def upstream(%__MODULE__{host: host, port: port}) when is_binary(host) and is_integer(port),
    do: "#{host}:#{port}"

  @spec url(t()) :: String.t()
  def url(%__MODULE__{protocol: protocol, host: host, port: port})
      when is_atom(protocol) and is_binary(host) and is_integer(port),
      do: "#{protocol}://#{host}:#{port}"
end
