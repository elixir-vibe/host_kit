defmodule HostKit.Resources.ConfigFile do
  @moduledoc "Structured INI/YAML config rendered to a managed file."

  @type format :: :ini | :yaml
  @type content :: map() | keyword()

  @type t :: %__MODULE__{
          path: String.t(),
          format: format(),
          content: content(),
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          depends_on: [term()],
          meta: map()
        }

  defstruct path: nil,
            format: nil,
            content: %{},
            owner: nil,
            group: nil,
            mode: nil,
            depends_on: [],
            meta: %{}

  @spec new(String.t(), format(), keyword()) :: t()
  def new(path, format, opts \\ []) when format in [:ini, :yaml] do
    %__MODULE__{
      path: path,
      format: format,
      content: Keyword.get(opts, :content, %{}),
      owner: normalize_account_name(Keyword.get(opts, :owner)),
      group: normalize_account_name(Keyword.get(opts, :group)),
      mode: opts |> Keyword.get(:mode) |> HostKit.Mode.normalize!(),
      depends_on: Keyword.get(opts, :depends_on, []),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def id(%__MODULE__{format: format, path: path}), do: {format, path}

  @spec secret?(t()) :: boolean()
  def secret?(%__MODULE__{content: content}), do: secret_value?(content)

  @spec public_entries(t()) :: map()
  def public_entries(%__MODULE__{format: :ini, content: content}) do
    content
    |> normalize_map()
    |> Enum.flat_map(&ini_public_entries/1)
    |> Map.new()
  end

  def public_entries(%__MODULE__{content: content}) do
    content
    |> public_tree()
    |> then(&%{content: &1})
  end

  @spec public_entries_from_content(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def public_entries_from_content(%__MODULE__{format: :ini} = desired, content) do
    public_keys = desired |> public_entries() |> Map.keys()

    with {:ok, entries} <- parse_ini(content) do
      {:ok, Map.take(entries, public_keys)}
    end
  end

  def public_entries_from_content(%__MODULE__{} = desired, content) do
    case render(%{desired | content: public_tree(desired.content)}) do
      {:ok, public_content} when public_content == content -> {:ok, public_entries(desired)}
      {:ok, _public_content} -> {:ok, :unknown}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec render(t()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{format: :ini, content: content}) do
    with {:ok, content} <- resolve_secrets(content) do
      {:ok, render_ini(content)}
    end
  end

  def render(%__MODULE__{format: :yaml, content: content}) do
    with {:ok, content} <- resolve_secrets(content) do
      {:ok, render_yaml(content)}
    end
  end

  defp render_ini(content) do
    content
    |> normalize_map()
    |> Enum.map(&ini_entry/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp ini_entry({section, values}) when is_map(values) or is_list(values) do
    [
      "[",
      to_string(section),
      "]\n",
      values |> normalize_map() |> Enum.map_join("\n", &ini_pair/1),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp ini_entry(pair), do: ini_pair(pair) <> "\n"

  defp ini_public_entries({section, values}) when is_map(values) or is_list(values) do
    values
    |> normalize_map()
    |> Enum.reject(fn {_key, value} -> secret_value?(value) end)
    |> Enum.map(fn {key, value} -> {{to_string(section), to_string(key)}, ini_value(value)} end)
  end

  defp ini_public_entries({key, value}) do
    if secret_value?(value), do: [], else: [{{nil, to_string(key)}, ini_value(value)}]
  end

  defp ini_pair({key, value}), do: "#{key}=#{ini_value(value)}"

  defp ini_value(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp ini_value(value), do: to_string(value)

  defp render_yaml(content) do
    content
    |> yaml_node(0)
    |> IO.iodata_to_binary()
  end

  defp yaml_node(%{} = map, indent), do: yaml_map(normalize_map(map), indent)

  defp yaml_node(values, indent) when is_list(values) do
    if Keyword.keyword?(values), do: yaml_map(values, indent), else: yaml_sequence(values, indent)
  end

  defp yaml_node(value, _indent), do: yaml_scalar(value)

  defp yaml_map(entries, indent) do
    separator = if indent == 0, do: "\n", else: ""

    entries
    |> Enum.map(fn {key, value} -> yaml_kv(key, value, indent) end)
    |> Enum.intersperse(separator)
  end

  defp yaml_sequence(values, indent) do
    separator = if Enum.any?(values, &map_like?/1), do: "\n", else: ""

    values
    |> Enum.map(&yaml_list_item(&1, indent))
    |> Enum.intersperse(separator)
  end

  defp yaml_kv(key, value, indent) when is_map(value) or is_list(value) do
    [spaces(indent), yaml_key(key), ":\n", yaml_node(value, indent + 2)]
  end

  defp yaml_kv(key, value, indent),
    do: [spaces(indent), yaml_key(key), ": ", yaml_scalar(value), "\n"]

  defp yaml_list_item(value, indent) when is_map(value) or is_list(value) do
    if map_like?(value) do
      pairs = normalize_map(value)

      case pairs do
        [] ->
          [spaces(indent), "- {}\n"]

        [{key, first} | rest] ->
          [yaml_first_list_pair(key, first, indent), yaml_rest_pairs(rest, indent + 2)]
      end
    else
      [spaces(indent), "- ", yaml_scalar(value), "\n"]
    end
  end

  defp yaml_list_item(value, indent), do: [spaces(indent), "- ", yaml_scalar(value), "\n"]

  defp yaml_first_list_pair(key, value, indent) when is_map(value) or is_list(value),
    do: [spaces(indent), "- ", yaml_key(key), ":\n", yaml_node(value, indent + 4)]

  defp yaml_first_list_pair(key, value, indent),
    do: [spaces(indent), "- ", yaml_key(key), ": ", yaml_scalar(value), "\n"]

  defp yaml_rest_pairs(pairs, indent),
    do: Enum.map(pairs, fn {key, value} -> yaml_kv(key, value, indent) end)

  defp yaml_key(key), do: yaml_scalar(to_string(key))

  defp yaml_scalar(value), do: Ymlr.Encode.to_s!(value)

  defp spaces(indent), do: String.duplicate(" ", indent)

  defp public_tree(%HostKit.Secret{}), do: nil
  defp public_tree(:redacted), do: nil

  defp public_tree(%{} = map) do
    map
    |> normalize_map()
    |> Enum.reject(fn {_key, value} -> secret_value?(value) end)
    |> Map.new(fn {key, value} -> {key, public_tree(value)} end)
  end

  defp public_tree(values) when is_list(values) do
    if Keyword.keyword?(values) do
      values
      |> Enum.reject(fn {_key, value} -> secret_value?(value) end)
      |> Enum.map(fn {key, value} -> {key, public_tree(value)} end)
    else
      Enum.reject(values, &secret_value?/1)
    end
  end

  defp public_tree(value), do: value

  defp resolve_secrets(%HostKit.Secret{} = secret) do
    {:ok, HostKit.Secret.resolve!(secret)}
  rescue
    error in [System.EnvError] -> {:error, {:missing_secret_env, error.env}}
  end

  defp resolve_secrets(:redacted), do: {:error, :redacted_secret_not_renderable}

  defp resolve_secrets(%{} = map), do: resolve_kv(normalize_map(map), %{})

  defp resolve_secrets(values) when is_list(values) do
    if Keyword.keyword?(values), do: resolve_kv(values, []), else: resolve_list(values)
  end

  defp resolve_secrets(value), do: {:ok, value}

  defp resolve_kv(entries, initial) do
    Enum.reduce_while(entries, {:ok, initial}, fn {key, value}, {:ok, acc} ->
      case resolve_secrets(value) do
        {:ok, value} -> {:cont, {:ok, put_entry(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case resolve_secrets(value) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp put_entry(acc, key, value) when is_map(acc), do: Map.put(acc, key, value)
  defp put_entry(acc, key, value) when is_list(acc), do: acc ++ [{key, value}]

  defp secret_value?(%HostKit.Secret{}), do: true
  defp secret_value?(:redacted), do: true
  defp secret_value?(%{} = map), do: Enum.any?(map, fn {_key, value} -> secret_value?(value) end)

  defp secret_value?(values) when is_list(values) do
    if Keyword.keyword?(values),
      do: Enum.any?(values, fn {_key, value} -> secret_value?(value) end),
      else: Enum.any?(values, &secret_value?/1)
  end

  defp secret_value?(_value), do: false

  defp parse_ini(content) do
    content
    |> String.split("\n")
    |> Enum.reduce_while({:ok, nil, %{}}, &parse_ini_line/2)
    |> case do
      {:ok, _section, entries} -> {:ok, entries}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_ini_line(line, {:ok, section, entries}) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, ["#", ";"]) ->
        {:cont, {:ok, section, entries}}

      String.starts_with?(line, "[") and String.ends_with?(line, "]") ->
        section = line |> String.trim_leading("[") |> String.trim_trailing("]")
        {:cont, {:ok, section, entries}}

      String.contains?(line, "=") ->
        [key, value] = String.split(line, "=", parts: 2)
        entries = Map.put(entries, {section, String.trim(key)}, String.trim(value))
        {:cont, {:ok, section, entries}}

      true ->
        {:halt, {:error, {:invalid_ini_line, line}}}
    end
  end

  defp normalize_map(value) when is_map(value),
    do: Enum.sort_by(value, fn {key, _value} -> to_string(key) end)

  defp normalize_map(value) when is_list(value) do
    if Keyword.keyword?(value), do: value, else: raise(ArgumentError, "expected keyword config")
  end

  defp map_like?(%{}), do: true
  defp map_like?(value) when is_list(value), do: Keyword.keyword?(value)
  defp map_like?(_value), do: false

  defp normalize_account_name(nil), do: nil
  defp normalize_account_name(name), do: HostKit.Account.name!(name)
end
