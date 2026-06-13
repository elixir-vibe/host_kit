defmodule HostKit.Mise.CLI do
  @moduledoc "mise runtime implementation backed by the mise CLI."

  @behaviour HostKit.Mise

  alias HostKit.Resources.Mise, as: MiseResource
  alias HostKit.Runner.Ops

  @impl true
  def read(%MiseResource{} = mise, context) do
    opts = Map.get(context, :opts, [])

    case mise_available?(mise, opts) do
      true ->
        {:ok, %{mise | meta: Map.put(mise.meta, :installed_tools, installed_tools(mise, opts))}}

      false ->
        {:ok, nil}
    end
  end

  @impl true
  def install(%MiseResource{} = mise, opts) do
    with :ok <- maybe_install_mise(mise, opts),
         :ok <- Ops.runner(opts) |> HostKit.Runner.mkdir_p(mise.system_data_dir, opts) do
      install_tools(mise, opts)
    end
  end

  defp maybe_install_mise(%MiseResource{install: false}, _opts), do: :ok

  defp maybe_install_mise(%MiseResource{} = mise, opts) do
    if mise_available?(mise, opts) do
      :ok
    else
      install_mise(mise, opts)
    end
  end

  defp install_mise(%MiseResource{path: path, version: version}, opts) do
    env = ["MISE_INSTALL_PATH=#{HostKit.Shell.escape(path)}", "MISE_QUIET=1", "MISE_NO_CONFIG=1"]
    env = if version, do: ["MISE_VERSION=#{HostKit.Shell.escape(version)}" | env], else: env

    Ops.cmd(opts, "sh", ["-c", "curl -fsSL https://mise.run | #{Enum.join(env, " ")} sh"])
  end

  defp install_tools(%MiseResource{tools: []}, _opts), do: :ok

  defp install_tools(%MiseResource{} = mise, opts) do
    tools = Enum.map_join(mise.tools, " ", &HostKit.Shell.escape(tool_arg(&1)))

    Ops.cmd(opts, "sh", [
      "-c",
      "#{mise_env(mise)} #{HostKit.Shell.escape(mise.path)} install --system #{tools}"
    ])
  end

  defp installed_tools(%MiseResource{} = mise, opts) do
    mise.tools
    |> Enum.filter(&tool_installed?(mise, &1, opts))
    |> Enum.map(&tool_key/1)
  end

  defp tool_installed?(%MiseResource{} = mise, tool, opts) do
    match?(
      :ok,
      Ops.cmd(opts, "sh", [
        "-c",
        mise_env(mise) <>
          " #{HostKit.Shell.escape(mise.path)} where #{HostKit.Shell.escape(tool_arg(tool))} >/dev/null"
      ])
    )
  end

  defp mise_available?(%MiseResource{path: path}, opts) do
    match?(:ok, Ops.cmd(opts, "sh", ["-c", "test -x #{HostKit.Shell.escape(path)}"]))
  end

  defp mise_env(%MiseResource{system_data_dir: system_data_dir}),
    do: "MISE_NO_CONFIG=1 MISE_SYSTEM_DATA_DIR=#{HostKit.Shell.escape(system_data_dir)}"

  defp tool_arg(%{name: name, version: version}), do: "#{name}@#{version}"
  defp tool_key(%{name: name, version: version}), do: {name, version}
end
