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

    assigns = opts |> Keyword.get(:assigns, %{}) |> normalize_assigns!()

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

  @spec secret?(t()) :: boolean()
  def secret?(%__MODULE__{assigns: assigns}), do: HostKit.Secret.secret?(assigns)

  @spec public_assigns(t()) :: map()
  def public_assigns(%__MODULE__{assigns: assigns}) do
    assigns
    |> Enum.reject(fn {_key, value} -> HostKit.Secret.secret?(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  @spec secret_assigns(t()) :: [String.t()]
  def secret_assigns(%__MODULE__{assigns: assigns}) do
    assigns
    |> Enum.filter(fn {_key, value} -> HostKit.Secret.secret?(value) end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.sort()
  end

  @spec render(t()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = template) do
    with {:ok, source} <- template_source(template),
         {:ok, assigns} <- resolve_assigns(template.assigns) do
      {:ok, EEx.eval_string(source, assigns_binding(assigns), []) |> IO.iodata_to_binary()}
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

  defp resolve_assigns(assigns) do
    Enum.reduce_while(assigns, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case resolve_assign(value) do
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, assigns} -> {:ok, assigns}
      error -> error
    end
  end

  defp resolve_assign(%HostKit.Secret{} = secret), do: HostKit.Secret.resolve(secret)

  defp resolve_assign(:redacted), do: {:error, :redacted_secret_not_renderable}
  defp resolve_assign(value), do: {:ok, value}

  defp assigns_binding(assigns) when is_map(assigns),
    do: [{:assigns, assigns} | Map.to_list(assigns)]

  defp assigns_binding(assigns) when is_list(assigns) do
    [{:assigns, Map.new(assigns)} | assigns]
  end

  defp normalize_assigns!(assigns) when is_map(assigns) do
    Map.new(assigns, fn {key, value} -> {normalize_assign_key!(key), value} end)
  end

  defp normalize_assigns!(assigns) when is_list(assigns) do
    Map.new(assigns, fn {key, value} -> {normalize_assign_key!(key), value} end)
  end

  defp normalize_assign_key!(key) when is_atom(key), do: key

  defp normalize_assign_key!(key) do
    raise ArgumentError, "template assign keys must be atoms, got: #{inspect(key)}"
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
