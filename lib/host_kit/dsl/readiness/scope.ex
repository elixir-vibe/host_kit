defmodule HostKit.DSL.Readiness.Scope do
  @moduledoc false

  use DSL

  options :readiness_opts, return: :keyword do
    field(:checks, {:array, :any}, default: [])
    field(:timeout, :integer, default: 60_000)
    field(:interval, :integer, default: 500)
    field(:depends_on, {:array, :any}, default: [])
    field(:meta, :map, default: %{})
  end

  options :systemd_check_opts, return: :keyword do
    field(:state, :atom, default: :active, in: [:active])
    field(:restart, :boolean, default: false)
    field(:kill, :boolean, default: false)
  end

  options :http_check_opts, return: :keyword do
    field(:status, :integer)
    field(:expect_status, :integer)
    field(:body, :string)
    field(:expect_body, :string)
  end

  scope(:readiness)

  def start(name, opts, source \\ nil) do
    push_readiness(
      HostKit.Resources.Readiness.new(name, validate_readiness_opts!(opts, location: source))
    )
  end

  def finish do
    pop_readiness()
  end

  def active?, do: readiness_active?()

  def systemd_check(unit, opts, source \\ nil) do
    HostKit.Readiness.Systemd.new(unit, validate_systemd_check_opts!(opts, location: source))
  end

  def http_check(url_or_opts, opts \\ [], source \\ nil)

  def http_check(opts, [], source) when is_list(opts) do
    opts = validate_http_check_opts!(opts, location: source)
    HostKit.Readiness.HTTP.new(opts)
  end

  def http_check(url, opts, source) do
    HostKit.Readiness.HTTP.new(url, validate_http_check_opts!(opts, location: source))
  end

  def add_check(check) do
    update_readiness(&%{&1 | checks: &1.checks ++ [check]})
  end
end
