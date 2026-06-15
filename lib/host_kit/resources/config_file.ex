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

  @spec render(t()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{format: :ini, content: content}), do: {:ok, render_ini(content)}
  def render(%__MODULE__{format: :yaml, content: content}), do: {:ok, render_yaml(content)}

  defp render_ini(content) do
    content
    |> normalize_map()
    |> Enum.map_join("\n", fn {section, values} ->
      [
        "[",
        to_string(section),
        "]\n",
        values |> normalize_map() |> Enum.map_join("\n", &ini_pair/1),
        "\n"
      ]
      |> IO.iodata_to_binary()
    end)
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
