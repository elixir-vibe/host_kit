defmodule HostKit.Mode do
  @moduledoc "Unix mode normalization helpers."

  @aliases %{
    public_file: 0o644,
    private_file: 0o600,
    secret_file: 0o600,
    secret_group_file: 0o640,
    secret_group_readable: 0o640,
    executable: 0o755,
    public_dir: 0o755,
    private_dir: 0o750,
    config_dir: 0o750,
    shared_dir: 0o2775,
    public_web_dir: 0o755,
    shared_web_dir: 0o2775
  }

  @class_bits %{read: 4, write: 2, execute: 1, r: 4, w: 2, x: 1}
  @capability_bits %{
    owner_r: 0o400,
    owner_w: 0o200,
    owner_x: 0o100,
    owner_rw: 0o600,
    owner_rx: 0o500,
    owner_rwx: 0o700,
    group_r: 0o040,
    group_w: 0o020,
    group_x: 0o010,
    group_rw: 0o060,
    group_rx: 0o050,
    group_rwx: 0o070,
    other_r: 0o004,
    other_w: 0o002,
    other_x: 0o001,
    other_rw: 0o006,
    other_rx: 0o005,
    other_rwx: 0o007,
    setuid: 0o4000,
    setgid: 0o2000,
    sticky: 0o1000
  }

  @spec normalize(term()) :: {:ok, non_neg_integer()} | {:error, term()}
  def normalize(nil), do: {:ok, nil}
  def normalize(mode) when is_integer(mode) and mode >= 0, do: {:ok, mode}

  def normalize(mode) when is_atom(mode) do
    case Map.fetch(@aliases, mode) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:unknown_mode_alias, mode}}
    end
  end

  def normalize({owner, group, other}), do: triplet(owner, group, other, 0)
  def normalize({:setgid, owner, group, other}), do: triplet(owner, group, other, 0o2000)
  def normalize({:setuid, owner, group, other}), do: triplet(owner, group, other, 0o4000)
  def normalize({:sticky, owner, group, other}), do: triplet(owner, group, other, 0o1000)

  def normalize(mode) when is_list(mode) do
    if Keyword.keyword?(mode) do
      keyword_mode(mode)
    else
      capability_mode(mode)
    end
  end

  def normalize(mode), do: {:error, {:invalid_mode, mode}}

  @spec normalize!(term()) :: non_neg_integer() | nil
  def normalize!(mode) do
    case normalize(mode) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, "invalid mode #{inspect(mode)}: #{inspect(reason)}"
    end
  end

  defp keyword_mode(mode) do
    owner = Keyword.get(mode, :owner, Keyword.get(mode, :user, Keyword.get(mode, :u)))
    group = Keyword.get(mode, :group, Keyword.get(mode, :g))
    other = Keyword.get(mode, :other, Keyword.get(mode, :o))
    special = special_bits(Keyword.get(mode, :special, []))

    with {:ok, special} <- special do
      triplet(owner, group, other, special)
    end
  end

  defp capability_mode(capabilities) do
    Enum.reduce_while(capabilities, {:ok, 0}, fn capability, {:ok, acc} ->
      case Map.fetch(@capability_bits, capability) do
        {:ok, bits} -> {:cont, {:ok, Bitwise.bor(acc, bits)}}
        :error -> {:halt, {:error, {:unknown_mode_capability, capability}}}
      end
    end)
  end

  defp triplet(owner, group, other, special) do
    with {:ok, owner} <- class_bits(owner),
         {:ok, group} <- class_bits(group),
         {:ok, other} <- class_bits(other) do
      {:ok, Bitwise.bor(special, owner * 0o100 + group * 0o10 + other)}
    end
  end

  defp class_bits(nil), do: {:ok, 0}
  defp class_bits(false), do: {:ok, 0}
  defp class_bits([]), do: {:ok, 0}
  defp class_bits(:none), do: {:ok, 0}
  defp class_bits(bits) when bits in [:r, :w, :x], do: class_bits([bits])
  defp class_bits(:rw), do: class_bits([:read, :write])
  defp class_bits(:rx), do: class_bits([:read, :execute])
  defp class_bits(:rwx), do: class_bits([:read, :write, :execute])

  defp class_bits(bits) when is_list(bits) do
    Enum.reduce_while(bits, {:ok, 0}, fn bit, {:ok, acc} ->
      case Map.fetch(@class_bits, bit) do
        {:ok, value} -> {:cont, {:ok, Bitwise.bor(acc, value)}}
        :error -> {:halt, {:error, {:unknown_mode_permission, bit}}}
      end
    end)
  end

  defp class_bits(other), do: {:error, {:invalid_mode_class, other}}

  defp special_bits(values) when values in [nil, false, []], do: {:ok, 0}
  defp special_bits(value) when is_atom(value), do: special_bits([value])

  defp special_bits(values) when is_list(values) do
    Enum.reduce_while(values, {:ok, 0}, fn value, {:ok, acc} ->
      case Map.fetch(@capability_bits, value) do
        {:ok, bits} when bits in [0o4000, 0o2000, 0o1000] ->
          {:cont, {:ok, Bitwise.bor(acc, bits)}}

        {:ok, _bits} ->
          {:halt, {:error, {:not_special_mode_bit, value}}}

        :error ->
          {:halt, {:error, {:unknown_special_mode_bit, value}}}
      end
    end)
  end
end
