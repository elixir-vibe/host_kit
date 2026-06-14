defmodule HostKit.RemoteTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.{Account, Directory, File}
  alias HostKit.Systemd

  defmodule FakeRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args, Keyword.delete(opts, :test_pid)})

      case {command, args} do
        {"getent", ["passwd", "app"]} ->
          {"app:x:1000:1000::/var/lib/app:/usr/sbin/nologin\n", 0}

        {"stat", ["-c", "%F:%U:%G:%a", "/srv/app"]} ->
          {"directory:app:app:750\n", 0}

        {"stat", ["-c", "%F:%U:%G:%a", "/etc/app/env"]} ->
          {"regular file:root:app:640\n", 0}

        {"sh", ["-c", "base64 '/etc/app/env'"]} ->
          {Base.encode64("PORT=4000\n"), 0}

        {"sudo", ["stat", "-c", "%F:%U:%G:%a", "/etc/systemd/system/app.service"]} ->
          {"regular file:root:root:644\n", 0}

        {"sh", ["-c", "sudo base64 '/etc/systemd/system/app.service'"]} ->
          {Base.encode64("[Unit]\nDescription=App\n"), 0}

        _ ->
          {"No such file", 1}
      end
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  test "reads accounts through a runner" do
    context = context()

    assert {:ok, %Account{home: "/var/lib/app", shell: "/usr/sbin/nologin"}} =
             HostKit.Remote.read(%Account{name: "app"}, context)
  end

  test "reads directory metadata through a runner" do
    assert {:ok, %Directory{owner: "app", group: "app", mode: 0o750}} =
             HostKit.Remote.read(%Directory{path: "/srv/app"}, context())
  end

  test "reads file metadata and content through a runner" do
    assert {:ok, %File{owner: "root", group: "app", mode: 0o640, content: "PORT=4000\n"}} =
             HostKit.Remote.read(%File{path: "/etc/app/env"}, context())
  end

  test "reads systemd units with sudo" do
    service = %Systemd.Service{name: "app.service", unit: [description: "App"]}

    assert {:ok, actual} = HostKit.Remote.read(service, context(sudo: true))
    assert actual.meta.content == "[Unit]\nDescription=App\n"
  end

  defp context(opts \\ []) do
    %{opts: Keyword.merge([runner: {FakeRunner, test_pid: self()}], opts), project: nil}
  end
end
