defmodule HostKit.LivebookDemoVM do
  @moduledoc false

  alias HostKit.{Host, Instance, Project}

  def main(["--" | args]), do: main(args)

  def main([command]) when command in ["ensure", "destroy", "status"] do
    apply(__MODULE__, String.to_existing_atom(command), [])
  end

  def main(_args) do
    IO.puts(:stderr, usage())
    System.halt(2)
  end

  def ensure do
    project = project()

    with {:ok, plan} <- HostKit.plan(project),
         {:ok, _results} <- HostKit.apply(plan, Keyword.merge(incus_opts(), confirm: true)) do
      print_ready()
    else
      {:error, reason} -> fail("could not ensure Livebook demo target", reason)
    end
  end

  def destroy do
    instance = instance()

    case HostKit.Instance.Backend.delete(instance, incus_opts()) do
      :ok -> :ok
      {:error, reason} -> fail("could not destroy Livebook demo target", reason)
    end
  end

  def status do
    instance = instance()

    case HostKit.Instance.Backend.read(instance, incus_opts()) do
      {:ok, %Instance{}} -> IO.puts("#{name()} is present")
      {:ok, nil} -> IO.puts("#{name()} is absent")
      {:error, reason} -> fail("could not read Livebook demo target", reason)
    end
  end

  defp project do
    Project.new(:livebook_demo)
    |> Project.add_instance(instance())
  end

  defp instance do
    host = %Host{
      name: :guest,
      hostname: "127.0.0.1",
      user: "root",
      sudo: false,
      meta: %{
        ssh: [
          user: "root",
          password: password(),
          port: ssh_port(),
          silently_accept_hosts: true
        ]
      }
    }

    Instance.new(name(), backend: :incus, image: image(), kind: kind(), lifecycle: :ephemeral)
    |> Instance.add_port(:ssh, host: ssh_port(), guest: 22)
    |> Instance.add_port(:caddy_demo, host: public_port(), guest: public_port())
    |> Instance.add_port(:phoenix_demo, host: phoenix_public_port(), guest: phoenix_public_port())
    |> Instance.add_host(host)
  end

  defp incus_opts do
    [
      incus: System.get_env("INCUS", "incus"),
      incus_sudo: env_true?("HOSTKIT_INCUS_SUDO")
    ]
  end

  defp print_ready do
    IO.puts("""

    Livebook target ready:
      Server:       127.0.0.1
      SSH user:     root
      SSH password: #{password()}
      SSH port:     #{ssh_port()}
      Caddy port:   #{public_port()}
      Phoenix port: #{phoenix_public_port()}
    """)
  end

  defp usage do
    """
    Usage: scripts/livebook_demo_vm.sh COMMAND

    Commands:
      ensure   Create/start a local Incus demo target with SSH password auth
      destroy  Delete the demo target
      status   Show target status

    Environment:
      HOSTKIT_LIVEBOOK_DEMO_VM           instance name (default: hostkit-livebook-demo)
      HOSTKIT_LIVEBOOK_DEMO_IMAGE        Incus image (default: images:ubuntu/24.04)
      HOSTKIT_LIVEBOOK_DEMO_TYPE         container or vm (default: container)
      HOSTKIT_LIVEBOOK_DEMO_SSH_PORT     host SSH port (default: 2222)
      HOSTKIT_LIVEBOOK_DEMO_PUBLIC_PORT  Caddy public demo port (default: 18080)
      HOSTKIT_LIVEBOOK_PHOENIX_PORT      Phoenix public demo port (default: 18081)
      HOSTKIT_LIVEBOOK_DEMO_PASSWORD     root password (default: hostkit-demo)
      HOSTKIT_INCUS_SUDO                 run incus through sudo: true/false (default: false)
      INCUS                              incus executable (default: incus)
    """
  end

  defp fail(message, reason) do
    IO.puts(:stderr, "#{message}: #{inspect(reason)}")
    System.halt(1)
  end

  defp name, do: env("HOSTKIT_LIVEBOOK_DEMO_VM", "hostkit-livebook-demo") |> String.to_atom()
  defp image, do: env("HOSTKIT_LIVEBOOK_DEMO_IMAGE", "images:ubuntu/24.04")
  defp password, do: env("HOSTKIT_LIVEBOOK_DEMO_PASSWORD", "hostkit-demo")
  defp ssh_port, do: env_integer("HOSTKIT_LIVEBOOK_DEMO_SSH_PORT", 2222)
  defp public_port, do: env_integer("HOSTKIT_LIVEBOOK_DEMO_PUBLIC_PORT", 18_080)
  defp phoenix_public_port, do: env_integer("HOSTKIT_LIVEBOOK_PHOENIX_PORT", 18_081)

  defp kind do
    case env("HOSTKIT_LIVEBOOK_DEMO_TYPE", "container") do
      "vm" -> :vm
      _other -> :container
    end
  end

  defp env(name, default), do: System.get_env(name, default)

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp env_true?(name), do: System.get_env(name) in ["1", "true", "TRUE", "yes"]
end

HostKit.LivebookDemoVM.main(System.argv())
