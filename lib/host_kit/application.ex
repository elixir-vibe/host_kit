defmodule HostKit.Application do
  @moduledoc "HostKit OTP application entry point."

  use Application

  @impl true
  def start(_type, _args) do
    HostKit.Supervisor.start_link([])
  end
end
