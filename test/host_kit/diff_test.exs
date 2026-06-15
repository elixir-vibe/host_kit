defmodule HostKit.DiffTest do
  use ExUnit.Case, async: true

  alias HostKit.Diff
  alias HostKit.Diff.Entry
  alias HostKit.Resources.ConfigFile

  test "builds structured entries using jsonpatch internally" do
    diff = Diff.structured(%{"server" => %{"port" => 4000}}, %{"server" => %{"port" => 4200}})

    assert %Diff{
             changes: [
               %Entry{op: :replace, path: ["server", "port"], before: 4000, after: 4200}
             ]
           } = diff
  end

  test "builds redaction-aware config file diffs" do
    config =
      ConfigFile.new("/etc/app.ini", :ini,
        content: [server: [DOMAIN: "new.example", TOKEN: :redacted]]
      )

    diff = Diff.config_file(config, %{{"server", "DOMAIN"} => "old.example"})

    assert diff == %Diff{
             format: :ini,
             changes: [
               %Entry{
                 op: :replace,
                 path: ["server", "DOMAIN"],
                 before: "old.example",
                 after: "new.example"
               }
             ],
             redacted_paths: [["server", "TOKEN"]]
           }
  end

  test "builds dotenv diffs" do
    env_file = %HostKit.Resources.EnvFile{
      entries: [{:set, "PORT", "4001"}, {:secret, "TOKEN", :redacted}]
    }

    diff = Diff.env_file(env_file, %{"PORT" => "4000"})

    assert diff == %Diff{
             format: :dotenv,
             changes: [%Entry{op: :replace, path: ["PORT"], before: "4000", after: "4001"}],
             redacted_paths: [["TOKEN"]]
           }
  end

  test "builds template assign diffs without rendered content" do
    template =
      HostKit.Resources.Template.new("/etc/app.conf",
        source: "port=<%= @port %>",
        assigns: %{port: 4000, token: :redacted}
      )

    diff = Diff.template(template)

    assert diff == %Diff{
             format: :template,
             changes: [%Entry{op: :replace, path: ["port"], before: :unknown, after: 4000}],
             redacted_paths: [["token"]]
           }
  end

  test "renders readable dotted and indexed paths" do
    assert Entry.render_path(["endpoints", 0, "url"]) == "endpoints[0].url"
  end
end
