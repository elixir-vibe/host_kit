defmodule HostKit.Account do
  @moduledoc "Account references and normalization helpers."

  defmodule Ref do
    @moduledoc "Reference to a declared HostKit account."
    defstruct [:name]
  end

  @type ref :: %Ref{name: atom() | String.t()}
  @type account_name :: atom() | String.t() | ref()

  @spec ref(atom() | String.t()) :: ref()
  def ref(name) when is_atom(name) or is_binary(name), do: %Ref{name: name}

  @spec name!(account_name()) :: String.t()
  def name!(%Ref{name: name}), do: name!(name)
  def name!(name) when is_atom(name), do: Atom.to_string(name)
  def name!(name) when is_binary(name), do: name

  def name!(other) do
    raise ArgumentError, "expected an account name or account reference, got: #{inspect(other)}"
  end
end

defimpl Inspect, for: HostKit.Account.Ref do
  import Inspect.Algebra

  def inspect(%HostKit.Account.Ref{name: name}, opts) do
    concat(["account(", to_doc(name, opts), ")"])
  end
end
