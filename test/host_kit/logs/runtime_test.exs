defmodule HostKit.LogsRuntimeTest do
  use ExUnit.Case, async: true

  defmodule Runner do
    @behaviour HostKit.Runner

    @impl true
    def cmd("journalctl", args, _opts) do
      send(self(), {:journalctl_args, args})

      {[
         Jason.encode!(%{"MESSAGE" => "started", "_SYSTEMD_UNIT" => "web.service"}),
         Jason.encode!(%{"MESSAGE" => "ready"})
       ]
       |> Enum.join("\n"), 0}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  defmodule FailingRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd("journalctl", _args, _opts), do: {"permission denied", 1}

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  test "reads journald JSON logs through runner" do
    assert {:ok, entries} = HostKit.Logs.read("web.service", runner: Runner, since: "1h")
    assert [%{"MESSAGE" => "started"}, %{"MESSAGE" => "ready"}] = entries

    assert_received {:journalctl_args,
                     ["-u", "web.service", "-o", "json", "--no-pager", "--since", "1h"]}
  end

  test "tails journald logs with line count" do
    assert {:ok, _entries} = HostKit.Logs.tail("web.service", runner: Runner, lines: 25)
    assert_received {:journalctl_args, args}
    assert Enum.take(args, -2) == ["-n", "25"]
  end

  test "returns journalctl failures" do
    assert {:error, {:journalctl_failed, 1, "permission denied"}} =
             HostKit.Logs.read("web.service", runner: FailingRunner)
  end
end
