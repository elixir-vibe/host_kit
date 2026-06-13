defmodule HostKit.PlanFormatTest do
  use ExUnit.Case, async: true

  alias HostKit.Addr.Resource
  alias HostKit.Change
  alias HostKit.Package.Resolution
  alias HostKit.Plan.Format
  alias HostKit.Resources.{Package, Source}

  test "formats a concise human-readable plan" do
    plan = %HostKit.Plan{
      changes: [
        %Change{action: :no_op, resource_id: {:directory, "/srv/app"}, reason: :in_sync},
        %Change{
          action: :update,
          resource_id: Resource.new(:caddy_site, :git),
          reason: :drift
        },
        %Change{
          action: :read,
          resource_id: {:file, "/etc/app/env"},
          reason: {:read_error, :eacces}
        }
      ]
    }

    assert Format.format(plan) ==
             String.trim_trailing("""
             Plan: 0 to create, 1 to update, 0 to delete, 1 read errors, 1 unchanged
             = directory./srv/app
               no_op in_sync
             ~ caddy_site.git
               update drift
             ? file./etc/app/env
               read {:read_error, :eacces}
             """)
  end

  test "formats source details" do
    plan = %HostKit.Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:source, :app},
          after: %Source{
            name: :app,
            uri: "https://github.com/elixir-vibe/host_kit.git",
            ref: "main",
            ref_kind: :branch,
            revision: "abc123",
            checkout: "/opt/app/source",
            path: "examples/hello"
          },
          reason: :missing
        }
      ]
    }

    assert Format.format(plan) ==
             String.trim_trailing("""
             Plan: 1 to create, 0 to update, 0 to delete, 0 read errors, 0 unchanged
             + source.app
               create missing
               type: git
               uri: https://github.com/elixir-vibe/host_kit.git
               ref: main (branch)
               resolved: abc123
               checkout: /opt/app/source
               path: examples/hello
             """)
  end

  test "formats package resolution details" do
    package = %Package{
      name: :openssl_dev,
      system_name: "libssl-dev",
      meta: %{
        resolution: %Resolution{
          package: "libssl-dev",
          source: :repology_cache,
          project: "openssl",
          repo: "debian_13"
        }
      }
    }

    plan = %HostKit.Plan{
      changes: [
        %Change{
          action: :create,
          resource_id: {:package, :openssl_dev},
          after: package,
          reason: :missing
        }
      ]
    }

    assert Format.format(plan) ==
             String.trim_trailing("""
             Plan: 1 to create, 0 to update, 0 to delete, 0 read errors, 0 unchanged
             + package.openssl_dev
               create missing
               resolves to libssl-dev via repology cache (openssl/debian_13)
             """)
  end
end
