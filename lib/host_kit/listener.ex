defmodule HostKit.Listener do
  @moduledoc "Named service listener metadata."

  @type t :: %__MODULE__{
          name: atom() | nil,
          port: pos_integer(),
          on: term(),
          protocol: atom(),
          meta: map()
        }

  defstruct name: nil,
            port: nil,
            on: nil,
            protocol: :http,
            meta: %{}

  @spec new(atom() | nil, keyword()) :: t()
  def new(name, opts) do
    %__MODULE__{
      name: name,
      port: Keyword.fetch!(opts, :port),
      on: opts |> Keyword.get(:on, :loopback) |> HostKit.Net.Addr.normalize!(),
      protocol: Keyword.get(opts, :protocol, :http),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @spec upstream(t()) :: String.t()
  def upstream(%__MODULE__{on: on, port: port}), do: "#{HostKit.Net.Addr.to_string(on)}:#{port}"
end
