defmodule HostKit.Resources.Command do
  @moduledoc "Declarative command step used for build/bootstrap workflows."

  @type exec :: {String.t(), [String.t()]}
  @type runtime :: nil | {:mise, atom()}

  @type t :: %__MODULE__{
          name: atom() | String.t(),
          exec: exec(),
          runtime: runtime(),
          cwd: String.t() | nil,
          env: %{String.t() => String.t()},
          creates: String.t() | nil,
          unless: String.t() | nil,
          inputs: [String.t() | HostKit.Source.Ref.t()],
          outputs: [String.t()],
          stamp: String.t() | nil,
          timeout: non_neg_integer() | nil,
          phase: atom() | nil,
          down: t() | :noop | :irreversible | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct name: nil,
            exec: nil,
            runtime: nil,
            cwd: nil,
            env: %{},
            creates: nil,
            unless: nil,
            inputs: [],
            outputs: [],
            stamp: nil,
            timeout: nil,
            phase: nil,
            down: nil,
            depends_on: [],
            meta: %{}

  @spec new(atom() | String.t(), keyword()) :: t()
  def new(name, opts) do
    %__MODULE__{
      name: name,
      exec: opts |> Keyword.fetch!(:exec) |> normalize_exec(),
      runtime: Keyword.get(opts, :runtime),
      cwd: Keyword.get(opts, :cwd),
      env: opts |> Keyword.get(:env, %{}) |> HostKit.Env.Normalize.string_map(),
      creates: Keyword.get(opts, :creates),
      unless: Keyword.get(opts, :unless),
      inputs:
        opts
        |> Keyword.get(:inputs, [])
        |> List.wrap()
        |> Enum.map(&HostKit.Source.Ref.normalize_input/1),
      outputs: opts |> Keyword.get(:outputs, []) |> List.wrap() |> Enum.map(&to_string/1),
      stamp: Keyword.get(opts, :stamp),
      timeout: Keyword.get(opts, :timeout),
      phase: Keyword.get(opts, :phase),
      down: normalize_down(name, Keyword.get(opts, :down), opts),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{name: name}), do: {:command, name}

  defp normalize_down(_name, policy, _opts) when policy in [nil, :noop, :irreversible], do: policy
  defp normalize_down(_name, %__MODULE__{} = command, _opts), do: command

  defp normalize_down(name, opts, parent_opts) when is_list(opts) do
    opts =
      opts
      |> Keyword.put_new(:name, "#{name}_down")
      |> inherit_parent(:runtime, parent_opts)
      |> inherit_parent(:cwd, parent_opts)
      |> inherit_parent(:env, parent_opts)
      |> inherit_parent(:timeout, parent_opts)

    new(Keyword.fetch!(opts, :name), opts)
  end

  defp normalize_down(name, exec, parent_opts),
    do: normalize_down(name, [exec: exec], parent_opts)

  defp inherit_parent(opts, key, parent_opts) do
    cond do
      Keyword.has_key?(opts, key) -> opts
      is_nil(Keyword.get(parent_opts, key)) -> opts
      true -> Keyword.put(opts, key, Keyword.fetch!(parent_opts, key))
    end
  end

  defp normalize_exec(%HostKit.CommandLine{command: command, args: args}), do: {command, args}

  defp normalize_exec(command) when is_binary(command),
    do: command |> HostKit.CommandLine.parse!() |> normalize_exec()

  defp normalize_exec({command, args}), do: {to_string(command), Enum.map(args, &to_string/1)}
  defp normalize_exec([command | args]), do: normalize_exec({command, args})
end
