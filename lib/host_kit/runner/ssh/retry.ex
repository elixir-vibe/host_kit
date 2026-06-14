defmodule HostKit.Runner.SSH.Retry do
  @moduledoc false

  @default_base_delay 250
  @default_max_delay 2_000

  @type policy :: %{
          attempts: pos_integer(),
          base_delay: non_neg_integer(),
          max_delay: non_neg_integer()
        }

  @spec normalize(term()) :: policy()
  def normalize(nil), do: disabled()
  def normalize(false), do: disabled()
  def normalize(true), do: normalize([])

  def normalize(attempts) when is_integer(attempts) do
    normalize(attempts: attempts)
  end

  def normalize(opts) when is_list(opts) do
    attempts = opts |> Keyword.get(:attempts, 1) |> positive_integer(:attempts)

    base_delay =
      opts
      |> Keyword.get(:base_delay, Keyword.get(opts, :base_delay_ms, @default_base_delay))
      |> non_negative_integer(:base_delay)

    max_delay =
      opts
      |> Keyword.get(:max_delay, Keyword.get(opts, :max_delay_ms, @default_max_delay))
      |> non_negative_integer(:max_delay)

    %{attempts: attempts, base_delay: base_delay, max_delay: max_delay}
  end

  def normalize(other) do
    raise ArgumentError,
          "expected SSH retry to be false, true, an attempts integer, or keyword options, got: #{inspect(other)}"
  end

  @spec delay(policy(), pos_integer()) :: non_neg_integer()
  def delay(%{base_delay: base_delay, max_delay: max_delay}, attempt) do
    multiplier = Integer.pow(2, max(attempt - 1, 0))
    min(base_delay * multiplier, max_delay)
  end

  defp disabled,
    do: %{attempts: 1, base_delay: @default_base_delay, max_delay: @default_max_delay}

  defp positive_integer(value, _name) when is_integer(value) and value >= 1, do: value

  defp positive_integer(value, name) do
    raise ArgumentError, "expected #{name} to be a positive integer, got: #{inspect(value)}"
  end

  defp non_negative_integer(value, _name) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value, name) do
    raise ArgumentError, "expected #{name} to be a non-negative integer, got: #{inspect(value)}"
  end
end
