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
    validate_name!(service, :service)
    validate_name!(name, :endpoint)

    %__MODULE__{
      service: service,
      name: name,
      protocol: validate_optional_protocol!(Keyword.get(opts, :protocol)),
      host: validate_optional_host!(Keyword.get(opts, :host)),
      port: validate_optional_port!(Keyword.get(opts, :port)),
      health: validate_optional_health!(Keyword.get(opts, :health)),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec declaration(atom() | String.t(), keyword()) :: t()
  def declaration(name, opts) do
    validate_name!(name, :endpoint)

    %__MODULE__{
      name: name,
      protocol: validate_protocol!(Keyword.get(opts, :protocol, :http)),
      host: validate_host!(Keyword.get(opts, :host, "127.0.0.1")),
      port: validate_port!(Keyword.fetch!(opts, :port)),
      health: validate_optional_health!(Keyword.get(opts, :health)),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  defp validate_name!(name, _label) when is_atom(name) or is_binary(name), do: name

  defp validate_name!(name, label) do
    raise ArgumentError, "#{label} name must be an atom or string, got: #{inspect(name)}"
  end

  defp validate_optional_protocol!(nil), do: nil
  defp validate_optional_protocol!(protocol), do: validate_protocol!(protocol)

  defp validate_protocol!(protocol) when protocol in [:http, :https], do: protocol

  defp validate_protocol!(protocol) do
    raise ArgumentError, "endpoint protocol must be :http or :https, got: #{inspect(protocol)}"
  end

  defp validate_optional_host!(nil), do: nil
  defp validate_optional_host!(host), do: validate_host!(host)

  defp validate_host!(host) when is_binary(host) and byte_size(host) > 0, do: host

  defp validate_host!(host) do
    raise ArgumentError, "endpoint host must be a non-empty string, got: #{inspect(host)}"
  end

  defp validate_optional_port!(nil), do: nil
  defp validate_optional_port!(port), do: validate_port!(port)

  defp validate_port!(port) when is_integer(port) and port in 1..65_535, do: port

  defp validate_port!(port) do
    raise ArgumentError, "endpoint port must be an integer from 1 to 65535, got: #{inspect(port)}"
  end

  defp validate_optional_health!(nil), do: nil
  defp validate_optional_health!(health) when is_binary(health), do: health

  defp validate_optional_health!(health) do
    raise ArgumentError, "endpoint health must be a string path, got: #{inspect(health)}"
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

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(endpoint, _opts) do
      suffix =
        if HostKit.Endpoint.resolved?(endpoint) do
          " #{HostKit.Endpoint.url(endpoint)}"
        else
          ""
        end

      concat([
        "#HostKit.Endpoint<",
        to_string(endpoint.service),
        ".",
        to_string(endpoint.name),
        suffix,
        ">"
      ])
    end
  end
end
