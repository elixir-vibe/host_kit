defmodule HostKit.LivebookDemo do
  alias Kino.Markdown
  alias HostKit.Runner.SSH.Connection

  def ssh_opts(settings) do
    identity_file = String.trim(settings.identity_file || "")

    [
      host: settings.server,
      user: settings.user,
      sudo: true,
      port: settings.ssh_port,
      silently_accept_hosts: true,
      retry: [attempts: Map.get(settings, :ssh_retries, 3)],
      connect_timeout: 5_000
    ]
    |> maybe_put(:identity_file, identity_file, &Path.expand/1)
    |> maybe_put(:password, settings.password)
  end

  def with_uploaded_key(%{key_file: %{file_ref: file_ref}} = settings) do
    source = Kino.Input.file_path(file_ref)

    path =
      Path.join(
        System.tmp_dir!(),
        "hostkit-livebook-ssh-key-#{System.unique_integer([:positive])}"
      )

    File.cp!(source, path)
    File.chmod!(path, 0o600)
    %{settings | identity_file: path}
  end

  def with_uploaded_key(settings), do: settings

  def check_ssh(settings) do
    case Connection.open(ssh_opts(settings)) do
      {:ok, conn} ->
        Connection.close(conn)
        Markdown.new("✅ **SSH works** — #{settings.user}@#{settings.server}:#{settings.ssh_port}")

      {:error, reason} ->
        Markdown.new("⚠️ **SSH failed** — `#{inspect(reason)}`")
    end
  end

  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  defp maybe_put(opts, _key, "", _fun), do: opts
  defp maybe_put(opts, key, value, fun), do: Keyword.put(opts, key, fun.(value))
end
