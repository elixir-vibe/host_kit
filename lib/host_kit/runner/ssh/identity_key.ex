defmodule HostKit.Runner.SSH.IdentityKey do
  @moduledoc "SSH key callback for a single OpenSSH identity file."

  @behaviour :ssh_client_key_api

  @impl true
  def user_key(_algorithm, opts) do
    opts
    |> key_path!()
    |> File.read!()
    |> :ssh_file.decode(:public_key)
    |> case do
      [{private_key, _attrs} | _rest] -> {:ok, private_key}
      {:error, reason} -> {:error, inspect(reason)}
      _other -> {:error, "identity file does not contain a private key"}
    end
  rescue
    error in [File.Error, KeyError, ArgumentError] -> {:error, Exception.message(error)}
  end

  @impl true
  def is_host_key(key, host, port, algorithm, opts) do
    :ssh_file.is_host_key(key, host, port, algorithm, opts)
  end

  @impl true
  def add_host_key(host, port, key, opts) do
    :ssh_file.add_host_key(host, port, key, opts)
  end

  defp key_path!(opts) do
    opts
    |> Keyword.fetch!(:key_cb_private)
    |> Keyword.fetch!(:identity_file)
    |> to_charlist()
  end
end
