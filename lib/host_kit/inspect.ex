defimpl Inspect, for: HostKit.Resources.Directory do
  import Inspect.Algebra

  def inspect(%HostKit.Resources.Directory{path: path}, _opts) do
    concat(["#HostKit.Directory<", path || "", ">"])
  end
end

defimpl Inspect, for: HostKit.Resources.File do
  import Inspect.Algebra

  def inspect(%HostKit.Resources.File{path: path}, _opts) do
    concat(["#HostKit.File<", path || "", ">"])
  end
end

defimpl Inspect, for: HostKit.Resources.Package do
  import Inspect.Algebra

  def inspect(%HostKit.Resources.Package{} = package, _opts) do
    resolved = if package.system_name, do: " -> #{package.system_name}", else: ""
    concat(["#HostKit.Package<", to_string(package.name), resolved, ">"])
  end
end

defimpl Inspect, for: HostKit.Resources.Readiness do
  import Inspect.Algebra

  def inspect(%HostKit.Resources.Readiness{name: name, checks: checks}, _opts) do
    concat([
      "#HostKit.Readiness<",
      to_string(name),
      " checks=",
      Integer.to_string(length(checks)),
      ">"
    ])
  end
end

defimpl Inspect, for: HostKit.Systemd.Service do
  import Inspect.Algebra

  def inspect(%HostKit.Systemd.Service{name: name}, _opts) do
    concat(["#HostKit.Systemd.Service<", name || "", ">"])
  end
end

defimpl Inspect, for: HostKit.Caddy.Site do
  import Inspect.Algebra

  def inspect(%HostKit.Caddy.Site{name: name, host: host}, _opts) do
    concat(["#HostKit.Caddy.Site<", to_string(name), " ", host || "", ">"])
  end
end
