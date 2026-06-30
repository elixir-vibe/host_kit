defmodule HostKit.Providers.GatusTest do
  use ExUnit.Case, async: true

  test "renders provider-neutral monitor endpoints as Gatus endpoints" do
    checks = [
      HostKit.Monitor.check(:http,
        name: "Forgejo",
        group: "elixir-toys",
        url: "https://git.elixir.toys",
        interval: "1m",
        expect: [status: 200, response_time_lt: 5000],
        alerts: [:telegram]
      )
    ]

    assert HostKit.Providers.Gatus.endpoints_from_monitors(checks) == [
             [
               name: "Forgejo",
               group: "elixir-toys",
               url: "https://git.elixir.toys",
               interval: "1m",
               conditions: ["[STATUS] == 200", "[RESPONSE_TIME] < 5000"],
               alerts: [[type: "telegram"]]
             ]
           ]
  end

  test "gatus_monitor_endpoints renders monitors from resources declared earlier" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatus]

      project :monitoring, providers: [HostKit.Providers.Gatus] do
        service :app do
          file "/srv/app/health.txt", content: "ok"

          monitor :http,
            name: "App",
            url: "https://app.example.com/health",
            expect: [status: 200, response_time_lt: 5000]
        end

        service :monitoring do
          gatus_config "/etc/gatus/gatus.yaml" do
            gatus_monitor_endpoints group: "demo", interval: "1m", alerts: [:telegram]
          end
        end
      end
      """)
      |> elem(0)

    assert [%HostKit.Resources.File{}, %HostKit.Resources.ConfigFile{} = config] =
             HostKit.Project.resources(project)

    assert Keyword.fetch!(config.content, :endpoints) == [
             [
               name: "App",
               group: "demo",
               url: "https://app.example.com/health",
               interval: "1m",
               conditions: ["[STATUS] == 200", "[RESPONSE_TIME] < 5000"],
               alerts: [[type: "telegram"]]
             ]
           ]
  end

  test "orders rendered monitor endpoints by name when requested" do
    checks = [
      HostKit.Monitor.check(:http, name: "B", url: "https://b.example.com"),
      HostKit.Monitor.check(:http, name: "A", url: "https://a.example.com")
    ]

    assert [first, second] = HostKit.Providers.Gatus.endpoints_from_monitors(checks, order: ["A"])
    assert first[:name] == "A"
    assert second[:name] == "B"
  end

  test "gatus_config emits a plain structured YAML resource" do
    project =
      Code.eval_string("""
      use HostKit.DSL, providers: [HostKit.Providers.Gatus]

      project :monitoring, providers: [HostKit.Providers.Gatus] do
        service :monitoring do
          gatus_config "/etc/gatus/gatus.yaml", owner: "root", group: service_user(), mode: 0o640 do
            web address: "127.0.0.1", port: 8080
            storage :sqlite, path: "/var/lib/gatus/gatus.db"

            telegram token: "${MONITORING_TELEGRAM_BOT_TOKEN}", id: "${MONITORING_TELEGRAM_CHAT_ID}" do
              default_alert enabled: true,
                "failure-threshold": 3,
                "success-threshold": 2,
                "send-on-resolved": true
            end

            gatus_endpoints HostKit.Providers.Gatus.endpoints_from_monitors([
              HostKit.Monitor.check(:http,
                name: "Forgejo",
                group: "elixir-toys",
                url: "https://git.elixir.toys",
                interval: "1m",
                expect: [status: 200, response_time_lt: 5000],
                alerts: [:telegram]
              )
            ])

            external_endpoint "Host health", group: "elixir-toys", token: "${GATUS_HOST_HEALTH_TOKEN}" do
              heartbeat interval: "30m"
              alert :telegram, description: "Host health failed", "send-on-resolved": true
            end
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
             ],
             "external-endpoints": [
               [
                 name: "Host health",
                 group: "elixir-toys",
                 token: "${GATUS_HOST_HEALTH_TOKEN}",
                 heartbeat: [interval: "30m"],
                 alerts: [
                   [
                     type: "telegram",
                     description: "Host health failed",
                     "send-on-resolved": true
                   ]
                 ]
               ]
             ]
           ]
  end
end
