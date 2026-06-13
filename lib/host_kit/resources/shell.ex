defmodule HostKit.Resources.Shell do
  @moduledoc "Validated Bash script resource for explicit shell execution."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          script: HostKit.ShellScript.t(),
          cwd: String.t() | nil,
          env: %{String.t() => String.t()},
          creates: String.t() | nil,
          unless: String.t() | nil,
          timeout: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            script: nil,
            cwd: nil,
            env: %{},
            creates: nil,
            unless: nil,
            timeout: nil,
            depends_on: [],
            meta: %{}

  def new(name, script, opts \\ []) do
    %__MODULE__{
      name: name,
      script: normalize_script(script),
      cwd: Keyword.get(opts, :cwd),
      env: opts |> Keyword.get(:env, %{}) |> HostKit.Env.Normalize.string_map(),
      creates: Keyword.get(opts, :creates),
      unless: Keyword.get(opts, :unless),
      timeout: Keyword.get(opts, :timeout),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:shell, name}

  defp normalize_script(%HostKit.ShellScript{} = script), do: script
  defp normalize_script(source) when is_binary(source), do: HostKit.ShellScript.parse!(source)
end
