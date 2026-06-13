defmodule HostKit.Package.Repology.RateLimitTest do
  use ExUnit.Case, async: false

  alias HostKit.Package.Repology.RateLimit

  test "wait enforces a one request per second API limit" do
    {elapsed, :ok} =
      :timer.tc(fn ->
        RateLimit.wait()
        RateLimit.wait()
      end)

    assert elapsed >= 900_000
  end

  test "wait can be disabled" do
    {elapsed, :ok} = :timer.tc(fn -> RateLimit.wait(rate_limit: false) end)

    assert elapsed < 100_000
  end
end
