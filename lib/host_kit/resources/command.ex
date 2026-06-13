defmodule HostKit.Resources.Command do
  @moduledoc "Declarative command step used for build/bootstrap workflows."

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          run: String.t(),
          cwd: String.t() | nil,
          env: %{String.t() => String.t()},
          creates: String.t() | nil,
          unless: String.t() | nil,
          timeout: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            run: nil,
            cwd: nil,
            env: %{},
            creates: nil,
            unless: nil,
            timeout: nil,
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts) do
    %__MODULE__{
      name: name,
      run: Keyword.fetch!(opts, :run),
      cwd: Keyword.get(opts, :cwd),
      env: opts |> Keyword.get(:env, %{}) |> normalize_env(),
      creates: Keyword.get(opts, :creates),
      unless: Keyword.get(opts, :unless),
      timeout: Keyword.get(opts, :timeout),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:command, name}

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp normalize_env(env) when is_list(env) do
    env |> Map.new() |> normalize_env()
  end
end
