defmodule HostKit.IntegrationCase do
  @moduledoc false

  defmacro on_exit_rollback(plan, target_opts, opts \\ []) do
    quote bind_quoted: [plan: plan, target_opts: target_opts, opts: opts] do
      down_opts = Keyword.take(opts, [:only, :except])
      apply_opts = Keyword.merge(target_opts, confirm: true)
      before_rollback = Keyword.get(opts, :before_rollback, fn -> :ok end)
      after_rollback = Keyword.get(opts, :after_rollback, fn -> :ok end)

      {:ok, down_plan} = HostKit.down(plan, down_opts)

      on_exit(fn ->
        before_rollback.()
        _result = HostKit.apply(down_plan, apply_opts)
        after_rollback.()
      end)

      down_plan
    end
  end
end
