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
      unit: opts |> Keyword.get(:unit, []) |> normalize_values(),
      service: opts |> Keyword.get(:service, []) |> normalize_values(),
      install: opts |> Keyword.get(:install, []) |> normalize_values(),
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

  defp normalize_values(values) do
    Enum.map(values, fn {key, value} -> {key, normalize_value(key, value)} end)
  end

  defp normalize_value(key, values) when key in [:after, :wants, :requires, :wanted_by],
    do: HostKit.Systemd.Target.names(values)

  defp normalize_value(:exec_start, argv) when is_list(argv), do: Enum.join(argv, " ")
  defp normalize_value(:restart, :on_failure), do: "on-failure"
  defp normalize_value(_key, value), do: value
end
