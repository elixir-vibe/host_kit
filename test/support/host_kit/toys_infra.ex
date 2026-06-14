defmodule HostKit.ToysInfra do
  @moduledoc false

  use HostKit.ProjectDSL

  root(:source, "/opt/toys/src")
  root(:data, "/srv/toys")
  root(:state, "/var/lib/toys")
  root(:config, "/etc/toys")
  root(:www, "/srv/toys/www")

  prefix(:user, "toys-")
  prefix(:unit, "toys-")

  defservice :toy_service do
    let(:service_user, do: prefixed(:user, service_name()))
    let(:unit_name, do: prefixed(:unit, service_name()) <> ".service")

    path(:source_dir, root(:source), path_name())
    path(:data_dir, root(:data), path_name())
    path(:state_dir, root(:state), path_name())
    path(:config_dir, root(:config), path_name())

    macro :standard_user do
      account(service_user(), system: true, home: state_path("home"))
    end

    macro :standard_dirs do
      directory(data_dir(), owner: service_user(), group: service_user(), mode: 0o755)
      directory(state_dir(), owner: service_user(), group: service_user(), mode: 0o755)
      directory(config_dir(), owner: service_user(), group: service_user(), mode: 0o755)
    end
  end
end
