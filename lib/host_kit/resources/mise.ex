defmodule HostKit.Resources.Mise do
  @moduledoc "Desired mise installation and system-wide tool versions."

  @type tool :: %{name: atom() | String.t(), version: String.t(), opts: keyword()}

  @type t :: %__MODULE__{
          name: atom(),
          path: String.t(),
          system_data_dir: String.t(),
          version: String.t() | nil,
          install: boolean(),
          tools: [tool()],
          depends_on: [term()],
          meta: map()
        }

  defstruct name: :mise,
            path: "/usr/local/bin/mise",
            system_data_dir: "/usr/local/share/mise",
            version: nil,
            install: true,
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
end
