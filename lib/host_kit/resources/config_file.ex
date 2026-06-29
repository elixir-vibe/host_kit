defmodule HostKit.Resources.ConfigFile do
  @moduledoc "Structured INI/YAML/TOML config rendered to a managed file."

  @type format :: :ini | :yaml | :toml
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
  def new(path, format, opts \\ []) when format in [:ini, :yaml, :toml] do
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
  def secret?(%__MODULE__{content: content}), do: HostKit.Secret.secret?(content)

  @spec public_entries(t()) :: map()
  def public_entries(%__MODULE__{format: :ini, content: content}) do
    content
    |> normalize_map()
    |> Enum.flat_map(&ini_public_entries/1)
    |> Map.new()
  end

  def public_entries(%__MODULE__{format: :yaml, content: content}) do
    content
    |> yaml_public_entries()
    |> Map.new()
  end

  def public_entries(%__MODULE__{format: :toml, content: content}) do
    content
    |> yaml_public_entries()
    |> Map.new()
  end

  @spec public_entries_from_content(t(), String.t()) :: {:ok, map()} | {:error, term()}
  def public_entries_from_content(%__MODULE__{format: :ini} = desired, content) do
    public_keys = desired |> public_entries() |> Map.keys()

    with {:ok, entries} <- parse_ini(content) do
      {:ok, Map.take(entries, public_keys)}
    end
  end

  def public_entries_from_content(%__MODULE__{format: :yaml} = desired, content) do
    public_keys = desired |> public_entries() |> Map.keys()

    with {:ok, decoded} <- parse_yaml(content) do
      {:ok, decoded |> yaml_public_entries() |> Map.new() |> Map.take(public_keys)}
    end
  end

  def public_entries_from_content(%__MODULE__{format: :toml} = desired, content) do
    public_keys = desired |> public_entries() |> Map.keys()

    with {:ok, decoded} <- parse_toml(content) do
      {:ok, decoded |> yaml_public_entries() |> Map.new() |> Map.take(public_keys)}
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

  def render(%__MODULE__{format: :toml, content: content}) do
    with {:ok, content} <- resolve_secrets(content) do
      {:ok, render_toml(content)}
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
    |> Enum.reject(fn {_key, value} -> HostKit.Secret.secret?(value) end)
    |> Enum.map(fn {key, value} -> {{to_string(section), to_string(key)}, ini_value(value)} end)
  end

  defp ini_public_entries({key, value}) do
    if HostKit.Secret.secret?(value), do: [], else: [{{nil, to_string(key)}, ini_value(value)}]
  end

  defp ini_secret_path_segments({section, values}) when is_map(values) or is_list(values) do
    values
    |> normalize_map()
    |> Enum.filter(fn {_key, value} -> HostKit.Secret.secret?(value) end)
    |> Enum.map(fn {key, _value} -> [to_string(section), to_string(key)] end)
  end

  defp ini_secret_path_segments({key, value}) do
    if HostKit.Secret.secret?(value), do: [[to_string(key)]], else: []
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

  defp yaml_public_entries(value), do: yaml_public_entries(value, [])

  defp yaml_public_entries(%HostKit.Secret{}, _path), do: []
  defp yaml_public_entries(:redacted, _path), do: []

  defp yaml_public_entries(%{} = map, path) do
    map
    |> normalize_map()
    |> Enum.flat_map(fn {key, value} -> yaml_public_entries(value, [to_string(key) | path]) end)
  end

  defp yaml_public_entries(values, path) when is_list(values) do
    if Keyword.keyword?(values) do
      Enum.flat_map(values, fn {key, value} ->
        yaml_public_entries(value, [to_string(key) | path])
      end)
    else
      values
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, index} -> yaml_public_entries(value, [index | path]) end)
    end
  end

  defp yaml_public_entries(value, path), do: [{path |> Enum.reverse() |> List.to_tuple(), value}]

  defp render_toml(content) do
    content
    |> normalize_map()
    |> toml_entries([])
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp toml_entries(entries, path) do
    {scalars, tables} = Enum.split_with(entries, fn {_key, value} -> toml_scalar_like?(value) end)

    scalar_lines = Enum.map(scalars, &toml_pair/1)
    table_lines = Enum.flat_map(tables, &toml_table(&1, path))

    case {path, scalar_lines, table_lines} do
      {[], [], table_lines} ->
        table_lines

      {[], scalar_lines, []} ->
        [toml_lines(scalar_lines)]

      {[], scalar_lines, table_lines} ->
        [toml_lines(scalar_lines) | table_lines]

      {_path, [], table_lines} ->
        table_lines

      {_path, scalar_lines, table_lines} ->
        [toml_header(path), toml_lines(scalar_lines) | table_lines]
    end
  end

  defp toml_table({key, values}, path) when is_map(values) do
    values
    |> normalize_map()
    |> toml_entries(path ++ [key])
  end

  defp toml_table({key, values}, path) when is_list(values) do
    if Keyword.keyword?(values) do
      values
      |> normalize_map()
      |> toml_entries(path ++ [key])
    else
      Enum.flat_map(values, fn
        value when is_map(value) -> toml_array_table(path ++ [key], normalize_map(value))
        value when is_list(value) -> toml_array_table(path ++ [key], normalize_map(value))
        _value -> [toml_pair({key, values})]
      end)
    end
  end

  defp toml_array_table(path, entries) do
    {scalars, tables} = Enum.split_with(entries, fn {_key, value} -> toml_scalar_like?(value) end)

    [
      toml_array_header(path),
      scalars |> Enum.map(&toml_pair/1) |> toml_lines()
      | Enum.flat_map(tables, &toml_table(&1, path))
    ]
  end

  defp toml_lines(entries), do: Enum.map_join(entries, "\n", & &1) <> "\n"

  defp toml_header(path), do: "[#{toml_path(path)}]"
  defp toml_array_header(path), do: "[[#{toml_path(path)}]]"
  defp toml_path(path), do: Enum.map_join(path, ".", &toml_key/1)

  defp toml_pair({key, value}), do: "#{toml_key(key)} = #{toml_value(value)}"

  defp toml_key(key) do
    key = to_string(key)

    if String.match?(key, ~r/^[A-Za-z0-9_-]+$/) do
      key
    else
      Jason.encode!(key)
    end
  end

  defp toml_value(value) when is_binary(value), do: Jason.encode!(value)
  defp toml_value(value) when is_boolean(value), do: if(value, do: "true", else: "false")
  defp toml_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp toml_value(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()

  defp toml_value(values) when is_list(values) do
    if Keyword.keyword?(values) do
      raise ArgumentError, "TOML inline tables are not supported; use nested tables"
    else
      values |> Enum.map_join(", ", &toml_value/1) |> then(&IO.iodata_to_binary(["[", &1, "]"]))
    end
  end

  defp toml_scalar_like?(value) when is_map(value), do: false

  defp toml_scalar_like?(value) when is_list(value) do
    cond do
      Keyword.keyword?(value) -> false
      Enum.all?(value, &(not map_like?(&1))) -> true
      true -> false
    end
  end

  defp toml_scalar_like?(_value), do: true

  defp spaces(indent), do: String.duplicate(" ", indent)

  @spec secret_path_segments(t()) :: [[String.t() | integer()]]
  def secret_path_segments(%__MODULE__{format: :ini, content: content}) do
    content
    |> normalize_map()
    |> Enum.flat_map(&ini_secret_path_segments/1)
    |> Enum.sort()
  end

  def secret_path_segments(%__MODULE__{format: :yaml, content: content}) do
    content
    |> yaml_secret_paths([])
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.sort()
  end

  def secret_path_segments(%__MODULE__{format: :toml, content: content}) do
    content
    |> yaml_secret_paths([])
    |> Enum.map(&Tuple.to_list/1)
    |> Enum.sort()
  end

  @spec secret_paths(t()) :: [String.t()]
  def secret_paths(%__MODULE__{} = config) do
    config
    |> secret_path_segments()
    |> Enum.map(&format_path_segments(config.format, &1))
  end

  @spec changed_public_paths(t(), map()) :: [String.t()]
  def changed_public_paths(%__MODULE__{} = desired, actual_entries) do
    desired
    |> changed_public_entries(actual_entries)
    |> Enum.map(& &1.path)
  end

  @spec changed_public_entries(t(), map() | :invalid | nil) :: [map()]
  def changed_public_entries(%__MODULE__{} = desired, actual_entries)
      when is_map(actual_entries) do
    desired
    |> public_entries()
    |> Enum.reject(fn {path, value} -> Map.get(actual_entries, path) == value end)
    |> Enum.map(fn {path, desired_value} ->
      %{
        path: format_public_path(desired.format, path),
        before: Map.get(actual_entries, path),
        after: desired_value
      }
    end)
    |> Enum.sort_by(& &1.path)
  end

  def changed_public_entries(%__MODULE__{} = desired, :invalid),
    do: unknown_public_entries(desired)

  def changed_public_entries(%__MODULE__{} = desired, nil), do: unknown_public_entries(desired)

  defp unknown_public_entries(%__MODULE__{} = desired) do
    desired
    |> public_entries()
    |> Enum.map(fn {path, desired_value} ->
      %{path: format_public_path(desired.format, path), before: :unknown, after: desired_value}
    end)
    |> Enum.sort_by(& &1.path)
  end

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

  defp yaml_secret_paths(%HostKit.Secret{}, path), do: [path |> Enum.reverse() |> List.to_tuple()]
  defp yaml_secret_paths(:redacted, path), do: [path |> Enum.reverse() |> List.to_tuple()]

  defp yaml_secret_paths(%{} = map, path) do
    map
    |> normalize_map()
    |> Enum.flat_map(fn {key, value} -> yaml_secret_paths(value, [to_string(key) | path]) end)
  end

  defp yaml_secret_paths(values, path) when is_list(values) do
    if Keyword.keyword?(values) do
      Enum.flat_map(values, fn {key, value} ->
        yaml_secret_paths(value, [to_string(key) | path])
      end)
    else
      values
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, index} -> yaml_secret_paths(value, [index | path]) end)
    end
  end

  defp yaml_secret_paths(_value, _path), do: []

  defp format_public_path(:ini, path), do: format_ini_path(path)
  defp format_public_path(:yaml, path), do: format_yaml_path(path)
  defp format_public_path(:toml, path), do: format_yaml_path(path)

  defp format_path_segments(:ini, [key]), do: key
  defp format_path_segments(:ini, [section, key]), do: "#{section}.#{key}"
  defp format_path_segments(:yaml, segments), do: format_yaml_path(segments)
  defp format_path_segments(:toml, segments), do: format_yaml_path(segments)

  defp format_ini_path({nil, key}), do: key
  defp format_ini_path({section, key}), do: "#{section}.#{key}"

  defp format_yaml_path(path) when is_tuple(path),
    do: path |> Tuple.to_list() |> format_yaml_path()

  defp format_yaml_path([]), do: "<root>"

  defp format_yaml_path(parts) do
    Enum.map_join(parts, ".", fn
      index when is_integer(index) -> Integer.to_string(index)
      key -> to_string(key)
    end)
  end

  defp parse_yaml(content) do
    YamlElixir.read_from_string(content)
  rescue
    error in [YamlElixir.ParsingError] -> {:error, {:invalid_yaml, Exception.message(error)}}
  end

  defp parse_toml(content) do
    Toml.decode(content, keys: :strings)
  end

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
