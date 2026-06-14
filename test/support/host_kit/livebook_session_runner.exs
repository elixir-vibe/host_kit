defmodule HostKit.LivebookSessionRunner do
  @moduledoc false

  @livebook_version "~> 0.19.8"
  @timeout 120_000

  def main(paths) when paths != [] do
    install_livebook!()

    for path <- paths do
      run!(path)
    end
  end

  def main(_paths) do
    raise "usage: elixir livebook_session_runner.exs NOTEBOOK [NOTEBOOK ...]"
  end

  def run!(path) do
    path = Path.expand(path)
    IO.puts("Running Livebook session validation for #{path}")

    {notebook, %{warnings: warnings}} =
      path
      |> File.read!()
      |> Livebook.LiveMarkdown.notebook_from_livemd()

    if warnings != [] do
      raise "Livebook import warnings for #{path}:\n" <> Enum.map_join(warnings, "\n", &"- #{&1}")
    end

    {:ok, session} = Livebook.Sessions.create_session(notebook: notebook)

    try do
      Livebook.Session.subscribe(session.id)

      Livebook.Session.register_client(
        session.pid,
        self(),
        Livebook.Users.User.new("hostkit-livebook-test")
      )

      Livebook.Session.connect_runtime(session.pid)
      await_runtime_connected!()

      evaluate_setup!(session.pid)
      evaluate_notebook_cells!(session.pid, demo_settings(path))
    after
      if Process.alive?(session.pid), do: Livebook.Session.close(session.pid)
    end

    :ok
  end

  defp install_livebook! do
    Mix.install(
      [{:livebook, @livebook_version}],
      config: [
        livebook: [
          {LivebookWeb.Endpoint,
           [
             adapter: Bandit.PhoenixAdapter,
             url: [host: "localhost", path: "/"],
             http: [ip: {127, 0, 0, 1}, port: 0],
             pubsub_server: Livebook.PubSub,
             live_view: [signing_salt: "livebook"],
             drainer: [shutdown: 1000],
             render_errors: [formats: [html: LivebookWeb.ErrorHTML], layout: false],
             live_reload: []
           ]},
          {Livebook.Apps.Manager, [retry_backoff_base_ms: 5_000]},
          feature_flags: []
        ],
        bun: [version: "1.3.10", assets: [args: ~w(), cd: "."]],
        phoenix: [json_library: JSON]
      ],
      start_applications: false
    )

    Application.put_all_env(
      [
        livebook: [
          serverless: true,
          cookie: :hostkit_livebook_test,
          random_boot_id: "hostkit-livebook-test",
          default_runtime: Livebook.Runtime.Standalone.new(),
          default_app_runtime: Livebook.Runtime.Standalone.new(),
          runtime_modules: [
            Livebook.Runtime.Standalone,
            Livebook.Runtime.Attached,
            Livebook.Runtime.Embedded
          ],
          data_path: Path.join(System.tmp_dir!(), "hostkit-livebook-validation"),
          home: File.cwd!(),
          agent_name: "default",
          allowed_uri_schemes: [],
          app_service_name: nil,
          app_service_url: nil,
          apps_banner: nil,
          authentication: :token,
          aws_credentials: false,
          force_ssl_host: nil,
          learn_notebooks: [],
          plugs: [],
          rewrite_on: [],
          shutdown_callback: nil,
          teams_auth: nil,
          teams_url: "https://teams.livebook.dev",
          github_release_info: %{repo: "livebook-dev/livebook", version: "0.19.8"},
          update_instructions_url: nil,
          within_iframe: false,
          k8s_kubeconfig_pipeline: Kubereq.Kubeconfig.Default,
          log_format: :text
        ]
      ],
      persistent: true
    )

    {:ok, _apps} = Application.ensure_all_started(:livebook)
  end

  defp await_runtime_connected! do
    receive_matching!(fn
      {:operations, ops} -> Enum.any?(ops, &match?({:runtime_connected, _, _}, &1))
      _ -> false
    end)
  end

  defp evaluate_setup!(session_pid) do
    case Livebook.Session.get_data(session_pid).notebook.setup_section do
      %{cells: [%{id: setup_id}]} ->
        evaluate_cell!(session_pid, setup_id)

      _ ->
        :ok
    end
  end

  defp evaluate_notebook_cells!(session_pid, settings) do
    session_pid
    |> evaluable_regular_cells()
    |> Enum.reduce(nil, fn cell, form ->
      if settings_receive_cell?(cell) and form != nil do
        submit_form!(form, settings)
      end

      case evaluate_cell!(session_pid, cell.id) do
        %{type: :control, attrs: %{type: :form}} = form -> form
        _output -> form
      end
    end)
  end

  defp evaluable_regular_cells(session_pid) do
    session_pid
    |> Livebook.Session.get_data()
    |> Map.fetch!(:notebook)
    |> Livebook.Notebook.evaluable_cells_with_section()
    |> Enum.reject(fn {cell, _section} -> cell.id == "setup" end)
    |> Enum.map(fn {cell, _section} -> cell end)
  end

  defp evaluate_cell!(session_pid, cell_id) do
    Livebook.Session.queue_cell_evaluation(session_pid, cell_id)

    receive_matching!(fn
      {:operations, ops} -> Enum.find_value(ops, &cell_response(&1, cell_id))
      _message -> false
    end)
  end

  defp cell_response(
         {:add_cell_evaluation_response, _client_id, response_cell_id, output, metadata},
         cell_id
       )
       when response_cell_id == cell_id do
    if metadata.errored do
      raise "Livebook cell #{cell_id} failed:\n#{inspect(output, pretty: true, limit: :infinity)}"
    end

    {:halt, output}
  end

  defp cell_response(_operation, _cell_id), do: false

  defp receive_matching!(matcher) do
    receive do
      message ->
        case matcher.(message) do
          {:halt, value} -> value
          true -> message
          false -> receive_matching!(matcher)
          nil -> receive_matching!(matcher)
        end
    after
      @timeout -> raise "timed out waiting for Livebook session operation"
    end
  end

  defp settings_receive_cell?(cell) do
    String.contains?(cell.source, "{:demo_settings")
  end

  defp submit_form!(%{destination: destination, ref: ref}, data) do
    send(
      destination,
      {:event, ref, %{origin: "hostkit-livebook-test", type: :submit, data: data}}
    )
  end

  defp env(name, default), do: System.get_env(name, default)

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end

  defp env_flag?(name), do: System.get_env(name) in ["1", "true", "yes"]

  defp demo_settings(path) do
    case Path.basename(path) do
      "deploy_caddy_site.livemd" ->
        %{
          server: env("HOSTKIT_LIVEBOOK_SERVER", "127.0.0.1"),
          user: env("HOSTKIT_LIVEBOOK_USER", System.get_env("USER") || "root"),
          ssh_port: env_integer("HOSTKIT_LIVEBOOK_SSH_PORT", 22),
          identity_file: env("HOSTKIT_LIVEBOOK_IDENTITY_FILE", "~/.ssh/id_ed25519"),
          password: env("HOSTKIT_LIVEBOOK_SSH_PASSWORD", ""),
          ssh_retries: env_integer("HOSTKIT_LIVEBOOK_SSH_RETRIES", 3),
          public_port: env_integer("HOSTKIT_LIVEBOOK_CADDY_PORT", 18_080),
          message: "Validated by HostKit Livebook session runner",
          apply?: env_flag?("HOSTKIT_LIVEBOOK_APPLY"),
          verify?: env_flag?("HOSTKIT_LIVEBOOK_VERIFY")
        }

      "deploy_phoenix_app.livemd" ->
        %{
          server: env("HOSTKIT_LIVEBOOK_SERVER", "127.0.0.1"),
          user: env("HOSTKIT_LIVEBOOK_USER", System.get_env("USER") || "root"),
          ssh_port: env_integer("HOSTKIT_LIVEBOOK_SSH_PORT", 22),
          identity_file: env("HOSTKIT_LIVEBOOK_IDENTITY_FILE", "~/.ssh/id_ed25519"),
          password: env("HOSTKIT_LIVEBOOK_SSH_PASSWORD", ""),
          ssh_retries: env_integer("HOSTKIT_LIVEBOOK_SSH_RETRIES", 3),
          public_hostname: env("HOSTKIT_LIVEBOOK_PHOENIX_HOSTNAME", "phoenix.example.com"),
          public_port: env_integer("HOSTKIT_LIVEBOOK_PHOENIX_PORT", 18_081),
          app_port: env_integer("HOSTKIT_LIVEBOOK_PHOENIX_APP_PORT", 14_000),
          source_repo:
            env("HOSTKIT_LIVEBOOK_SOURCE_REPO", "https://github.com/elixir-vibe/host_kit.git"),
          source_ref: env("HOSTKIT_LIVEBOOK_SOURCE_REF", "master"),
          package_repo: env("HOSTKIT_LIVEBOOK_PACKAGE_REPO", "ubuntu_24_04"),
          erlang_version: env("HOSTKIT_LIVEBOOK_ERLANG", "29.0.2"),
          elixir_version: env("HOSTKIT_LIVEBOOK_ELIXIR", "1.20.1"),
          apply?: env_flag?("HOSTKIT_LIVEBOOK_APPLY"),
          verify?: env_flag?("HOSTKIT_LIVEBOOK_VERIFY")
        }

      other ->
        raise "no demo settings fixture for #{other}"
    end
  end
end

HostKit.LivebookSessionRunner.main(System.argv())
