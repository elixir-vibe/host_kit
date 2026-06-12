defmodule HostKit.Plugins.Systemd do
  @moduledoc "Core HostKit plugin for persistent systemd units."

  @behaviour HostKit.Plugin

  @impl true
  def dsl_modules, do: [HostKit.DSL.Systemd]

  @impl true
  def resource_types, do: [HostKit.Systemd.Service, HostKit.Systemd.Timer]

  @impl true
  def render(%HostKit.Systemd.Service{} = service, _context),
    do: {:ok, HostKit.Systemd.Service.render(service)}

  def render(%HostKit.Systemd.Timer{} = timer, _context),
    do: {:ok, HostKit.Systemd.Timer.render(timer)}

  def render(_resource, _context), do: :ignore

  @impl true
  def validate(%HostKit.Systemd.Service{} = service, _context),
    do: HostKit.Systemd.Service.validate(service)

  def validate(%HostKit.Systemd.Timer{} = timer, _context),
    do: HostKit.Systemd.Timer.validate(timer)

  def validate(_resource, _context), do: :ignore
end
