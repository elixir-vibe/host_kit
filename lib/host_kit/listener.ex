defmodule HostKit.Listener do
  @moduledoc "Named service listener metadata."

  @type t :: %__MODULE__{
          name: atom() | nil,
          port: pos_integer() | nil,
          socket: String.t() | nil,
          on: term(),
          protocol: atom(),
          meta: map()
        }

  defstruct name: nil,
            port: nil,
            socket: nil,
            on: nil,
            protocol: :http,
            meta: %{}

  @spec new(atom() | nil, keyword()) :: t()
  def new(name, opts) do
    protocol = Keyword.get(opts, :protocol, :http)
    port = Keyword.get(opts, :port)
    socket = Keyword.get(opts, :socket)

    validate_endpoint!(protocol, port, socket)

    %__MODULE__{
      name: name,
      port: port,
      socket: socket,
      on: opts |> Keyword.get(:on, :loopback) |> HostKit.Net.Addr.normalize!(),
      protocol: protocol,
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  defp validate_endpoint!(:rpc, port, socket)
       when is_integer(port) or (is_binary(socket) and byte_size(socket) > 0),
       do: :ok

  defp validate_endpoint!(:rpc, _port, _socket) do
    raise ArgumentError, "rpc listener requires a port or socket"
  end

  defp validate_endpoint!(_protocol, port, _socket) when is_integer(port), do: :ok

  defp validate_endpoint!(protocol, _port, _socket) do
    raise ArgumentError, "#{protocol} listener requires a port"
  end

  @spec upstream(t()) :: String.t()
  def upstream(%__MODULE__{socket: socket}) when is_binary(socket), do: "unix:#{socket}"

  def upstream(%__MODULE__{on: on, port: port}) when is_integer(port),
    do: "#{HostKit.Net.Addr.to_string(on)}:#{port}"
end
