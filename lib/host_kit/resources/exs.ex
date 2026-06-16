defmodule HostKit.Resources.Exs do
  @moduledoc "Desired `.exs` file rendered from quoted Elixir AST."

  @type t :: %__MODULE__{
          path: String.t(),
          ast: Macro.t(),
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            ast: nil,
            owner: nil,
            group: nil,
            mode: nil,
            depends_on: [],
            meta: %{}

  @spec new(String.t(), Macro.t(), keyword()) :: t()
  def new(path, ast, opts \\ []) do
    %__MODULE__{
      path: path,
      ast: ast,
      owner: normalize_account_name(Keyword.get(opts, :owner)),
      group: normalize_account_name(Keyword.get(opts, :group)),
      mode: opts |> Keyword.get(:mode) |> HostKit.Mode.normalize!(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{path: path}), do: {:exs, path}

  @spec secret?(t()) :: boolean()
  def secret?(%__MODULE__{ast: ast}), do: secret_ast?(ast)

  @spec render(t()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{ast: ast}) do
    with {:ok, ast} <- render_ast(ast) do
      {:ok, ast |> Macro.to_string() |> Kernel.<>("\n")}
    end
  rescue
    exception in [ArgumentError, FunctionClauseError, System.EnvError] ->
      {:error, {exception.__struct__, Exception.message(exception)}}
  end

  defp render_ast(ast) do
    ast
    |> Macro.prewalk(:ok, fn
      {:unquote, _meta, [{:value, _value_meta, [value_ast]}]}, :ok ->
        {:ok, value} = literal(value_ast)
        {Macro.escape(value), :ok}

      {:unquote, _meta, [{:secret, _secret_meta, [key_ast, opts_ast]}]}, :ok ->
        {:ok, _key} = literal(key_ast)
        {:ok, opts} = literal(opts_ast)
        secret = HostKit.Secret.from_opts!(opts)
        {Macro.escape(HostKit.Secret.resolve!(secret)), :ok}

      {:unquote, _meta, [{:secret, _secret_meta, [key_ast]}]}, :ok ->
        {:ok, key} = literal(key_ast)
        {Macro.escape(HostKit.Secret.resolve!(HostKit.Secret.env(key))), :ok}

      node, :ok ->
        {node, :ok}
    end)
    |> case do
      {ast, :ok} -> {:ok, ast}
    end
  end

  defp secret_ast?({:unquote, _meta, [{:secret, _secret_meta, _args}]}), do: true

  defp secret_ast?(ast) when is_tuple(ast) do
    ast |> Tuple.to_list() |> Enum.any?(&secret_ast?/1)
  end

  defp secret_ast?(ast) when is_list(ast), do: Enum.any?(ast, &secret_ast?/1)
  defp secret_ast?(_ast), do: false

  defp literal(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_atom(value),
       do: {:ok, value}

  defp literal(values) when is_list(values) do
    if Keyword.keyword?(values), do: keyword_literal(values), else: list_literal(values)
  end

  defp literal({:%{}, _meta, entries}), do: map_literal(entries)
  defp literal(_ast), do: {:error, :unsupported_exs_placeholder_value}

  defp keyword_literal(values) do
    values
    |> Enum.reduce_while({:ok, []}, &keyword_literal_entry/2)
    |> reverse_ok()
  end

  defp keyword_literal_entry({key, value}, {:ok, acc}) do
    case literal(value) do
      {:ok, value} -> {:cont, {:ok, [{key, value} | acc]}}
      error -> {:halt, error}
    end
  end

  defp list_literal(values) do
    values
    |> Enum.reduce_while({:ok, []}, &list_literal_entry/2)
    |> reverse_ok()
  end

  defp list_literal_entry(value, {:ok, acc}) do
    case literal(value) do
      {:ok, value} -> {:cont, {:ok, [value | acc]}}
      error -> {:halt, error}
    end
  end

  defp map_literal(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, &map_literal_entry/2)
  end

  defp map_literal_entry({key, value}, {:ok, acc}) do
    case {literal(key), literal(value)} do
      {{:ok, key}, {:ok, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
      {{:error, _reason} = error, _value} -> {:halt, error}
      {_key, {:error, _reason} = error} -> {:halt, error}
    end
  end

  defp reverse_ok({:ok, values}), do: {:ok, Enum.reverse(values)}
  defp reverse_ok(error), do: error

  defp normalize_account_name(nil), do: nil
  defp normalize_account_name(name), do: HostKit.Account.name!(name)
end
