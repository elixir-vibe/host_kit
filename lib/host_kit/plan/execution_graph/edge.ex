defmodule HostKit.Plan.ExecutionGraph.Edge do
  @moduledoc "A dependency edge in a HostKit plan execution graph."

  @type reason ::
          :explicit_dependency
          | :parent_directory
          | :owner_account
          | :group_account
          | :source_input
          | :readiness_systemd
          | :symlink_target_path
          | :systemd_timer_service
          | :systemd_environment_file
          | :systemd_environment_path
          | :systemd_exec_path
          | :systemd_read_write_path

  @type source :: :declared | :derived

  @type t :: %__MODULE__{
          from: term(),
          to: term(),
          reason: reason(),
          detail: term(),
          source: source()
        }

  @enforce_keys [:from, :to, :reason, :source]
  defstruct [:from, :to, :reason, :detail, :source]
end
