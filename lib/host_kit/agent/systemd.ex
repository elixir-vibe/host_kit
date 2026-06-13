defmodule HostKit.Agent.Systemd do
  @moduledoc "Helpers for declaring HostKit agent systemd units."

  @spec service(keyword()) :: HostKit.Systemd.Service.t()
  def service(opts) do
    name = Keyword.get(opts, :name, "host-kit.service")
    exec_start = Keyword.fetch!(opts, :exec_start)

    %HostKit.Systemd.Service{
      name: name,
      unit: [
        description: Keyword.get(opts, :description, "HostKit agent"),
        after: ["network-online.target"]
      ],
      service: [
        type: "simple",
        exec_start: normalize_exec_start(exec_start),
        restart: "on-failure",
        standard_output: "journal",
        standard_error: "journal",
        syslog_identifier: Keyword.get(opts, :identifier, "host-kit")
      ],
      install: [wanted_by: ["multi-user.target"]],
      meta: %{hostkit_agent: true}
    }
  end

  defp normalize_exec_start(argv) when is_list(argv), do: Enum.join(argv, " ")
  defp normalize_exec_start(command) when is_binary(command), do: command
end
