defmodule HostKit.CommandSuccessCodesTest do
  use ExUnit.Case, async: true

  alias HostKit.Resources.Command

  defmodule ExitRunner do
    @behaviour HostKit.Runner

    @impl true
    def cmd(command, args, opts) do
      send(opts[:test_pid], {:cmd, command, args})
      {"exit", opts[:exit_status]}
    end

    @impl true
    def mkdir_p(_path, _opts), do: :ok

    @impl true
    def write_file(_path, _content, _opts), do: :ok
  end

  test "command success_codes accepts modeled non-zero statuses" do
    command =
      Command.new(:stop_unit, exec: {"systemctl", ["stop", "app.service"]}, success_codes: [0, 5])

    plan = %HostKit.Plan{
      changes: [
        %HostKit.Change{
          action: :create,
          resource_id: HostKit.Resource.id(command),
          after: command,
          reason: :missing
        }
      ]
    }

    assert {:ok, [%{status: :applied}]} =
             HostKit.Apply.run(plan,
               confirm: true,
               runner: {ExitRunner, test_pid: self(), exit_status: 5}
             )

    assert_received {:cmd, "systemctl", ["stop", "app.service"]}
  end
end
