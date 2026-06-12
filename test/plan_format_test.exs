defmodule HostKit.PlanFormatTest do
  use ExUnit.Case, async: true

  alias HostKit.Addr.Resource
  alias HostKit.Change
  alias HostKit.Plan.Format

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
end
