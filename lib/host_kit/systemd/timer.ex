defmodule HostKit.Systemd.Timer do
  @moduledoc "Persistent systemd timer unit declaration backed by systemdkit rendering."

  @type t :: %__MODULE__{
          name: String.t(),
          unit: keyword(),
          timer: keyword(),
          install: keyword(),
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            unit: [],
            timer: [],
            install: [],
            depends_on: [],
            meta: %{}

  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      unit: opts |> Keyword.get(:unit, []) |> HostKit.Systemd.Directives.coerce(),
      timer: opts |> Keyword.get(:timer, []) |> HostKit.Systemd.Directives.coerce(),
      install: opts |> Keyword.get(:install, []) |> HostKit.Systemd.Directives.coerce(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:systemd_timer, name}

  @spec unit_file(t()) :: struct()
  def unit_file(%__MODULE__{} = timer) do
    Systemd.UnitFile.timer(
      unit: timer.unit,
      timer: timer.timer,
      install: timer.install
    )
  end

  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = timer) do
    timer
    |> unit_file()
    |> Systemd.UnitFile.to_string()
  end

  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = timer) do
    timer
    |> unit_file()
    |> Systemd.UnitFile.validate(:timer)
  end
end
