defmodule HostKit.Host do
  @moduledoc "Host declaration."

  @type t :: %__MODULE__{
          name: atom(),
          hostname: String.t() | nil,
          user: String.t() | nil,
          sudo: boolean(),
          meta: map()
        }

  defstruct name: nil,
            hostname: nil,
            user: nil,
            sudo: true,
            meta: %{}

  @spec target_opts(t(), keyword()) :: keyword()
  def target_opts(%__MODULE__{} = host, overrides \\ []) do
    [target: HostKit.Target.ssh(host.name, ssh_options(host, overrides)), reader: HostKit.Remote]
  end

  @spec ssh_options(t(), keyword()) :: keyword()
  def ssh_options(%__MODULE__{} = host, overrides \\ []) do
    host
    |> remote_options()
    |> Keyword.merge(overrides)
    |> resolve_secrets()
  end

  @spec remote_options(t()) :: keyword()
  def remote_options(%__MODULE__{} = host) do
    host.meta
    |> Map.get(:ssh, [])
    |> Keyword.put_new(:host, host.hostname)
    |> Keyword.put_new(:user, host.user)
    |> Keyword.put_new(:sudo, host.sudo)
  end

  defp resolve_secrets(opts) do
    case Keyword.fetch(opts, :password) do
      {:ok, password} -> Keyword.put(opts, :password, HostKit.Secret.resolve!(password))
      :error -> opts
    end
  end
end
