defmodule HostKit.Runtime.Resources do
  @moduledoc "Reusable cgroup resource controls for systemd-backed runtimes."

  @type t :: %__MODULE__{
          memory_max: String.t() | non_neg_integer() | nil,
          memory_high: String.t() | non_neg_integer() | nil,
          cpu_quota: String.t() | nil,
          cpu_weight: pos_integer() | nil,
          tasks_max: non_neg_integer() | nil,
          io_weight: pos_integer() | nil
        }

  defstruct memory_max: nil,
            memory_high: nil,
            cpu_quota: nil,
            cpu_weight: nil,
            tasks_max: nil,
            io_weight: nil

  @spec new(map() | keyword() | atom()) :: t()
  def new(profile) when is_atom(profile), do: profile(profile)
  def new(attrs) when is_list(attrs) or is_map(attrs), do: struct!(__MODULE__, attrs)

  @spec profile(atom()) :: t()
  def profile(:small), do: new(memory_max: "512M", cpu_quota: "50%", tasks_max: 128)
  def profile(:medium), do: new(memory_max: "1G", cpu_quota: "100%", tasks_max: 256)
  def profile(:large), do: new(memory_max: "2G", cpu_quota: "200%", tasks_max: 512)
  def profile(:vibe_dev), do: new(memory_max: "2G", cpu_quota: "150%", tasks_max: 512)
  def profile(:strict_app), do: profile(:small)
  def profile(:untrusted), do: new(memory_max: "1G", cpu_quota: "100%", tasks_max: 256)
end

defimpl HostKit.Systemd.ServiceOptions, for: HostKit.Runtime.Resources do
  def service_options(resources) do
    resources
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end
end
