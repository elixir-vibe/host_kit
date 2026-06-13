defmodule HostKit.Runtime.Sandbox do
  @moduledoc "Reusable process sandbox options for systemd-backed runtimes."

  @type protect_system :: :full | :strict | boolean() | nil
  @type address_family :: :inet | :inet6 | :unix | String.t()

  @type t :: %__MODULE__{
          no_new_privileges: boolean() | nil,
          private_tmp: boolean() | nil,
          private_devices: boolean() | nil,
          private_network: boolean() | nil,
          protect_system: protect_system(),
          protect_home: boolean() | String.t() | nil,
          protect_clock: boolean() | nil,
          protect_hostname: boolean() | nil,
          protect_kernel_tunables: boolean() | nil,
          protect_kernel_modules: boolean() | nil,
          protect_kernel_logs: boolean() | nil,
          protect_control_groups: boolean() | nil,
          lock_personality: boolean() | nil,
          restrict_realtime: boolean() | nil,
          restrict_suid_sgid: boolean() | nil,
          remove_ipc: boolean() | nil,
          system_call_architectures: atom() | String.t() | nil,
          restrict_address_families: [address_family()] | String.t() | nil,
          read_write_paths: [String.t()],
          read_only_paths: [String.t()],
          inaccessible_paths: [String.t()]
        }

  defstruct no_new_privileges: nil,
            private_tmp: nil,
            private_devices: nil,
            private_network: nil,
            protect_system: nil,
            protect_home: nil,
            protect_clock: nil,
            protect_hostname: nil,
            protect_kernel_tunables: nil,
            protect_kernel_modules: nil,
            protect_kernel_logs: nil,
            protect_control_groups: nil,
            lock_personality: nil,
            restrict_realtime: nil,
            restrict_suid_sgid: nil,
            remove_ipc: nil,
            system_call_architectures: nil,
            restrict_address_families: nil,
            read_write_paths: [],
            read_only_paths: [],
            inaccessible_paths: []

  @spec new(map() | keyword() | atom()) :: t()
  def new(profile) when is_atom(profile), do: profile(profile)
  def new(attrs) when is_list(attrs) or is_map(attrs), do: struct!(__MODULE__, attrs)

  @spec profile(atom()) :: t()
  def profile(:none), do: %__MODULE__{}

  def profile(:web_service) do
    new(
      no_new_privileges: true,
      private_tmp: true,
      private_devices: true,
      protect_system: :full,
      protect_home: true,
      restrict_address_families: [:inet, :inet6, :unix]
    )
  end

  def profile(:vibe_dev) do
    new(
      no_new_privileges: true,
      private_tmp: true,
      protect_system: :full,
      restrict_suid_sgid: true,
      restrict_address_families: [:inet, :inet6, :unix]
    )
  end

  def profile(:strict_app), do: profile(:strict_web)

  def profile(:untrusted) do
    %__MODULE__{} = strict_web = profile(:strict_web)
    %__MODULE__{strict_web | private_network: true}
  end

  def profile(:strict_web) do
    %__MODULE__{} = web_service = profile(:web_service)

    %__MODULE__{
      web_service
      | protect_system: :strict,
        protect_clock: true,
        protect_hostname: true,
        protect_kernel_tunables: true,
        protect_kernel_modules: true,
        protect_kernel_logs: true,
        protect_control_groups: true,
        lock_personality: true,
        restrict_realtime: true,
        restrict_suid_sgid: true,
        remove_ipc: true,
        system_call_architectures: :native
    }
  end

  @spec to_systemd_service_options(t()) :: keyword()
  def to_systemd_service_options(%__MODULE__{} = sandbox) do
    sandbox
    |> Map.from_struct()
    |> Enum.reject(fn
      {_key, nil} -> true
      {_key, []} -> true
      _entry -> false
    end)
    |> Enum.map(fn
      {:restrict_address_families, families} ->
        {:restrict_address_families, address_families(families)}

      entry ->
        entry
    end)
  end

  defp address_families(families) when is_binary(families), do: families

  defp address_families(families) when is_list(families) do
    families
    |> Enum.map_join(" ", fn
      :inet -> "AF_INET"
      :inet6 -> "AF_INET6"
      :unix -> "AF_UNIX"
      family -> to_string(family)
    end)
  end
end
