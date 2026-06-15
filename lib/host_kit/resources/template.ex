defmodule HostKit.Resources.Template do
  @moduledoc "Desired file content rendered from an EEx template."

  @type assigns :: map() | keyword()

  @type t :: %__MODULE__{
          path: String.t(),
          source: String.t() | nil,
          from: String.t() | nil,
          assigns: assigns(),
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            source: nil,
            from: nil,
            assigns: %{},
            owner: nil,
            group: nil,
            mode: nil,
            depends_on: [],
            meta: %{}

  @spec new(String.t(), keyword()) :: t()
  def new(path, opts \\ []) do
    source = Keyword.get(opts, :source)
    from = normalize_from(Keyword.get(opts, :from), Keyword.get(opts, :base_dir))

    if is_nil(source) and is_nil(from) do
      raise ArgumentError, "template #{inspect(path)} expects :from or :source"
    end

    assigns = Keyword.get(opts, :assigns, %{})

    if HostKit.Secret.secret?(assigns) do
      raise ArgumentError,
            "template #{inspect(path)} assigns cannot contain secrets until redacted template diffs are supported"
    end

    %__MODULE__{
      path: path,
      source: source,
      from: from,
      assigns: assigns,
      owner: normalize_account_name(Keyword.get(opts, :owner)),
      group: normalize_account_name(Keyword.get(opts, :group)),
      mode: opts |> Keyword.get(:mode) |> HostKit.Mode.normalize!(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{path: path}), do: {:template, path}

  @spec render(t()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = template) do
    with {:ok, source} <- template_source(template) do
      {:ok,
       EEx.eval_string(source, assigns_binding(template.assigns), []) |> IO.iodata_to_binary()}
    end
  rescue
    exception in [
      EEx.SyntaxError,
      SyntaxError,
      CompileError,
      ArgumentError,
      KeyError,
      UndefinedFunctionError,
      FunctionClauseError,
      MatchError,
      ArithmeticError
    ] ->
      {:error, {exception.__struct__, Exception.message(exception)}}
  end

  defp template_source(%__MODULE__{source: source}) when is_binary(source), do: {:ok, source}

  defp template_source(%__MODULE__{from: from}) when is_binary(from), do: File.read(from)

  defp assigns_binding(assigns) when is_map(assigns),
    do: [{:assigns, assigns} | Map.to_list(assigns)]

  defp assigns_binding(assigns) when is_list(assigns) do
    [{:assigns, Map.new(assigns)} | assigns]
  end

  defp normalize_from(nil, _base_dir), do: nil

  defp normalize_from(path, base_dir) do
    cond do
      Path.type(path) == :absolute -> path
      is_binary(base_dir) -> Path.expand(path, base_dir)
      true -> path
    end
  end

  defp normalize_account_name(nil), do: nil
  defp normalize_account_name(name), do: HostKit.Account.name!(name)
end
