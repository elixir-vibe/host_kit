defmodule HostKit.Agent.Systemd do
  @moduledoc "Helpers for declaring HostKit agent systemd units."

  @spec service(keyword()) :: HostKit.Systemd.Service.t()
  def service(opts) do
    HostKit.Systemd.Service.new(Keyword.get(opts, :name, "host-kit.service"),
      unit: [
        description: Keyword.get(opts, :description, "HostKit agent"),
        after: :network_online
      ],
      service: [
        type: "simple",
        exec_start: Keyword.fetch!(opts, :exec_start),
        restart: :on_failure,
        standard_output: "journal",
        standard_error: "journal",
        syslog_identifier: Keyword.get(opts, :identifier, "host-kit")
      ],
      install: [wanted_by: :multi_user],
      meta: %{hostkit_agent: true}
    )
  end
end
