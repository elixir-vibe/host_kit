defmodule HostKit.Providers.GatusTest do
  use ExUnit.Case, async: true

  test "gatus_config emits a plain structured YAML resource" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatus]

      project :monitoring, providers: [HostKit.Providers.Gatus] do
        service :monitoring do
          gatus_config "/etc/gatus/gatus.yaml", owner: "root", group: service_user(), mode: 0o640 do
            web address: "127.0.0.1", port: 8080
            gatus_storage :sqlite, path: "/var/lib/gatus/gatus.db"

            telegram_alerting token: "${MONITORING_TELEGRAM_BOT_TOKEN}", id: "${MONITORING_TELEGRAM_CHAT_ID}" do
              default_alert enabled: true,
                "failure-threshold": 3,
                "success-threshold": 2,
                "send-on-resolved": true
            end

            gatus_endpoint "Forgejo",
              group: "elixir-toys",
              url: "https://git.elixir.toys",
              interval: "1m",
              conditions: ["[STATUS] == 200", "[RESPONSE_TIME] < 5000"],
              alerts: [:telegram]
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Resources.ConfigFile{} = config] = HostKit.Project.resources(project)
    assert config.path == "/etc/gatus/gatus.yaml"
    assert config.format == :yaml
    assert config.owner == "root"
    assert config.group == "monitoring"
    assert config.mode == 0o640

    assert config.content == [
             web: [address: "127.0.0.1", port: 8080],
             storage: [type: "sqlite", path: "/var/lib/gatus/gatus.db"],
             alerting: [
               telegram: [
                 token: "${MONITORING_TELEGRAM_BOT_TOKEN}",
                 id: "${MONITORING_TELEGRAM_CHAT_ID}",
                 "default-alert": [
                   enabled: true,
                   "failure-threshold": 3,
                   "success-threshold": 2,
                   "send-on-resolved": true
                 ]
               ]
             ],
             endpoints: [
               [
                 name: "Forgejo",
                 group: "elixir-toys",
                 url: "https://git.elixir.toys",
                 interval: "1m",
                 conditions: ["[STATUS] == 200", "[RESPONSE_TIME] < 5000"],
                 alerts: [[type: "telegram"]]
               ]
             ]
           ]
  end
end
