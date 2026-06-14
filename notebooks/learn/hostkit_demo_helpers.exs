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

  def target_form(defaults \\ []) do
    defaults = Map.new(defaults)
    caller = self()

    form =
      Kino.Control.form(
        [
          server: Kino.Input.text("Server", default: Map.get(defaults, :server, "127.0.0.1")),
          user: Kino.Input.text("SSH user", default: Map.get(defaults, :user, "root")),
          password:
            Kino.Input.password("SSH password", default: Map.get(defaults, :password, "")),
          key_file: Kino.Input.file("Upload SSH key"),
          identity_file:
            Kino.Input.text("SSH key path on server",
              default: Map.get(defaults, :identity_file, "")
            ),
          ssh_port: Kino.Input.number("SSH port", default: Map.get(defaults, :ssh_port, 22)),
          public_port:
            Kino.Input.number("Public port", default: Map.get(defaults, :public_port, 18_080)),
          message:
            Kino.Input.text("Message",
              default: Map.get(defaults, :message, "Deployed by HostKit")
            )
        ],
        submit: "Check SSH connection"
      )

    status = Kino.Frame.new()

    Kino.Frame.render(
      status,
      Markdown.new("Enter SSH details and click **Check SSH connection**.")
    )

    Kino.listen(form, fn %{type: :submit, data: settings} ->
      settings = with_uploaded_key(settings)
      send(caller, {:demo_settings, settings})
      Kino.Frame.render(status, check_ssh(settings))
    end)

    Kino.Layout.grid([form, status], columns: 1)
  end

  def await_target(_form) do
    receive do
      {:demo_settings, settings} -> settings
    end
  end

  def check_ssh(settings) do
    case Connection.open(ssh_opts(settings)) do
      {:ok, conn} ->
        Connection.close(conn)
        Markdown.new("✅ **SSH works** — #{settings.user}@#{settings.server}:#{settings.ssh_port}")

      {:error, reason} ->
        Markdown.new("⚠️ **SSH failed** — #{ssh_error(reason)}")
    end
  end

  def plan_summary(plan) do
    counts = Enum.frequencies_by(plan.changes, & &1.action)

    Markdown.new("""
    ### Plan

    **#{Map.get(counts, :create, 0)}** create · **#{Map.get(counts, :update, 0)}** update · **#{Map.get(counts, :delete, 0)}** delete · **#{Map.get(counts, :no_op, 0)}** unchanged · **#{Map.get(counts, :read, 0)}** read errors
    """)
  end

  def plan_table(plan) do
    plan.changes
    |> Enum.map(fn change ->
      resource = resource_parts(change.resource_id)

      %{
        action: change.action,
        type: resource.type,
        name: resource.name,
        status: format_reason(change.reason)
      }
    end)
    |> Kino.DataTable.new(
      keys: [:action, :type, :name, :status],
      name: "Plan changes",
      num_rows: 20
    )
  end

  def collect_apply_progress do
    Stream.repeatedly(fn ->
      receive do
        {HostKit.Apply, event} -> HostKit.Apply.Event.format(event)
      after
        0 -> nil
      end
    end)
    |> Enum.take_while(& &1)
  end

  def apply_summary({:ok, results}, progress) when is_list(results) do
    counts = Enum.frequencies_by(results, &Map.get(&1, :status, :unknown))

    Markdown.new("""
    ### Deploy summary

    - Applied: #{Map.get(counts, :applied, 0)}
    - Skipped: #{Map.get(counts, :skipped, 0)}
    - Failed: #{Map.get(counts, :failed, 0)}
    - Events: #{length(progress)}
    """)
  end

  def apply_summary(other, progress) do
    Markdown.new("""
    ### Deploy result

    - Result: `#{inspect(other)}`
    - Events: #{length(progress)}
    """)
  end

  def apply_table({:ok, results}) when is_list(results) do
    results
    |> Enum.map(fn result ->
      change = Map.get(result, :change)
      resource = change && resource_parts(change.resource_id)

      %{
        status: Map.get(result, :status),
        action: change && change.action,
        type: resource && resource.type,
        name: resource && resource.name
      }
    end)
    |> Kino.DataTable.new(
      keys: [:status, :action, :type, :name],
      name: "Deploy results",
      num_rows: 20
    )
  end

  def apply_table(result),
    do: Kino.DataTable.new([%{result: inspect(result)}], name: "Deploy result")

  def verify_summary(response, public_url) do
    Markdown.new("""
    ### Verify

    ✅ Site is reachable

    - Status: `#{response.status}`
    - URL: [#{public_url}](#{public_url})
    """)
  end

  defp resource_parts(%HostKit.Addr.Resource{} = resource) do
    %{type: to_string(resource.type), name: to_string(resource.name)}
  end

  defp resource_parts({type, name}), do: %{type: to_string(type), name: to_string(name)}
  defp resource_parts(other), do: %{type: "resource", name: inspect(other)}

  defp format_reason(nil), do: "in sync"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp ssh_error(reason) when is_list(reason) do
    reason
    |> List.to_string()
    |> ssh_error()
  rescue
    _error -> inspect(reason)
  end

  defp ssh_error(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "Unable to connect using the available authentication methods") ->
        "authentication failed. Check the SSH user, password, or uploaded key."

      String.contains?(reason, "Connection refused") ->
        "connection refused. Check the server address and SSH port."

      true ->
        reason
    end
  end

  defp ssh_error(reason), do: inspect(reason)

  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
  defp maybe_put(opts, _key, "", _fun), do: opts
  defp maybe_put(opts, key, value, fun), do: Keyword.put(opts, key, fun.(value))
end
