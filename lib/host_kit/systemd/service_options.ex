defprotocol HostKit.Systemd.ServiceOptions do
  @moduledoc "Converts values into systemd [Service] options."

  @spec service_options(t()) :: keyword()
  def service_options(value)
end

defimpl HostKit.Systemd.ServiceOptions, for: List do
  def service_options(values), do: values
end
