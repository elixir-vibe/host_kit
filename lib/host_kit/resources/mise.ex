defmodule HostKit.Resources.Mise do
  @moduledoc "Desired mise installation and system-wide tool versions."

  @type tool :: %{name: atom() | String.t(), version: String.t(), opts: keyword()}

  @type packages :: false | :auto | :common | [atom() | String.t()]

  @type t :: %__MODULE__{
          name: atom(),
          path: String.t(),
          system_data_dir: String.t(),
          version: String.t() | nil,
          install: boolean(),
          packages: packages(),
          tools: [tool()],
          depends_on: [term()],
          meta: map()
        }

  defstruct name: :mise,
            path: "/usr/local/bin/mise",
            system_data_dir: "/usr/local/share/mise",
            version: nil,
            install: true,
            packages: :auto,
            tools: [],
            depends_on: [],
            meta: %{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(__MODULE__, Map.new(opts))
  end

  @spec id(t()) :: {:mise, atom()}
  def id(%__MODULE__{name: name}), do: {:mise, name}

  @spec add_tool(t(), atom() | String.t(), String.t(), keyword()) :: t()
  def add_tool(%__MODULE__{} = mise, name, version, opts \\ []) do
    tool = %{name: name, version: to_string(version), opts: opts}
    %{mise | tools: mise.tools ++ [tool]}
  end

  @spec package_resources(t()) :: [
          HostKit.Resources.Package.t() | HostKit.Resources.Capability.t()
        ]
  def package_resources(%__MODULE__{} = mise) do
    mise
    |> package_names()
    |> Enum.uniq()
    |> Enum.map(&package_resource/1)
  end

  defp package_names(%__MODULE__{packages: false}), do: []
  defp package_names(%__MODULE__{packages: :common}), do: common_packages()
  defp package_names(%__MODULE__{packages: packages}) when is_list(packages), do: packages

  defp package_names(%__MODULE__{packages: :auto} = mise) do
    common_packages() ++ tool_packages(mise.tools)
  end

  defp tool_packages(tools) do
    if Enum.any?(tools, &beam_tool?/1), do: beam_build_packages(), else: []
  end

  defp beam_tool?(%{name: name}) when name in [:erlang, :elixir], do: true
  defp beam_tool?(%{name: name}) when name in ["erlang", "elixir"], do: true
  defp beam_tool?(_tool), do: false

  defp package_resource(:cxx_compiler) do
    HostKit.Resources.Capability.new(:cxx_compiler, candidates: ["g++", "gcc-c++"])
  end

  defp package_resource(name), do: HostKit.Resources.Package.new(name)

  defp common_packages, do: [:curl, :ca_certificates]

  defp beam_build_packages do
    [
      :git,
      :autoconf,
      :make,
      :gcc,
      :cxx_compiler,
      :perl,
      :m4,
      :openssl_dev,
      :ncurses_dev,
      :unzip,
      :xsltproc
    ]
  end
end
