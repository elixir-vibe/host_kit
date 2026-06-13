defmodule HostKit.Systemd.Service do
  @moduledoc "Persistent systemd service unit declaration backed by systemdkit rendering."

  @type t :: %__MODULE__{
          name: String.t(),
          unit: keyword(),
          service: keyword(),
          install: keyword(),
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            unit: [],
            service: [],
            install: [],
            depends_on: [],
            meta: %{}

  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      unit: opts |> Keyword.get(:unit, []) |> HostKit.Systemd.Directives.coerce(),
      service: opts |> Keyword.get(:service, []) |> HostKit.Systemd.Directives.coerce(),
      install: opts |> Keyword.get(:install, []) |> HostKit.Systemd.Directives.coerce(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:systemd_service, name}

  @spec unit_file(t()) :: struct()
  def unit_file(%__MODULE__{} = service) do
    Systemd.UnitFile.service(
      unit: service.unit,
      service: service.service,
      install: service.install
    )
  end

  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = service) do
    service
    |> unit_file()
    |> Systemd.UnitFile.to_string()
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = service) do
    service
    |> unit_file()
    |> Systemd.UnitFile.validate(:service)
  end
end
