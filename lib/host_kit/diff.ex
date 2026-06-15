defmodule HostKit.Diff do
  @moduledoc "Structured, redaction-aware review diffs for HostKit plan changes."

  alias HostKit.Diff.Entry

  defstruct format: nil, changes: [], redacted_paths: []

  @type format :: :ini | :yaml | :dotenv | :template | :structured
  @type t :: %__MODULE__{
          format: format(),
          changes: [Entry.t()],
          redacted_paths: [[String.t() | integer()]]
        }

  @spec structured(map(), map(), keyword()) :: t()
  def structured(before_tree, after_tree, opts \\ [])
      when is_map(before_tree) and is_map(after_tree) do
    format = Keyword.get(opts, :format, :structured)
    redacted_paths = Keyword.get(opts, :redacted_paths, [])

    %__MODULE__{
      format: format,
      changes:
        before_tree
        |> Jsonpatch.diff(after_tree)
        |> Enum.map(&entry(&1, before_tree, after_tree)),
      redacted_paths: redacted_paths
    }
  end

  @spec env_file(HostKit.Resources.EnvFile.t(), map() | :invalid | nil) :: t()
  def env_file(%HostKit.Resources.EnvFile{} = desired, actual_entries) do
    desired_entries = HostKit.Env.public_entries(desired)
    redacted_paths = Enum.map(HostKit.Env.secret_paths(desired), &[&1])

    diff_from_entries(:dotenv, desired_entries, actual_entries, redacted_paths)
  end

  @spec config_file(HostKit.Resources.ConfigFile.t(), map() | :invalid | nil) :: t()
  def config_file(%HostKit.Resources.ConfigFile{} = desired, actual_entries) do
    desired_entries = HostKit.Resources.ConfigFile.public_entries(desired)
    redacted_paths = HostKit.Resources.ConfigFile.secret_path_segments(desired)

    diff_from_entries(desired.format, desired_entries, actual_entries, redacted_paths)
  end

  @spec template(HostKit.Resources.Template.t(), HostKit.Resources.Template.t() | nil) :: t()
  def template(%HostKit.Resources.Template{} = desired, actual \\ nil) do
    desired_assigns = HostKit.Resources.Template.public_assigns(desired)
    actual_assigns = if actual, do: HostKit.Resources.Template.public_assigns(actual), else: nil

    redacted_paths =
      Enum.map(HostKit.Resources.Template.secret_assigns(desired), &[to_string(&1)])

    diff_from_entries(:template, desired_assigns, actual_assigns, redacted_paths)
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{changes: [], redacted_paths: []}), do: true
  def empty?(%__MODULE__{}), do: false

  defp diff_from_entries(format, desired_entries, actual_entries, redacted_paths) do
    case actual_entries do
      actual_entries when is_map(actual_entries) ->
        before_tree = entries_tree(actual_entries)
        after_tree = entries_tree(desired_entries)

        structured(before_tree, after_tree, format: format, redacted_paths: redacted_paths)

      _unknown ->
        %__MODULE__{
          format: format,
          changes:
            desired_entries
            |> Enum.map(fn {path, after_value} ->
              %Entry{
                op: :replace,
                path: path_segments(path),
                before: :unknown,
                after: after_value
              }
            end)
            |> Enum.sort_by(&Entry.render_path/1),
          redacted_paths: redacted_paths
        }
    end
  end

  defp entry(%{op: op, path: pointer}, before_tree, after_tree) do
    path = parse_pointer(pointer)

    %Entry{
      op: normalize_op(op),
      path: path,
      before: value_at(before_tree, path),
      after: value_at(after_tree, path)
    }
  end

  defp normalize_op(op) when is_binary(op), do: String.to_existing_atom(op)
  defp normalize_op(op) when is_atom(op), do: op

  defp entries_tree(entries) do
    Enum.reduce(entries, %{}, fn {path, value}, acc ->
      put_path(acc, path_segments(path), value)
    end)
  end

  defp put_path(_tree, [], value), do: value

  defp put_path(tree, [key], value) do
    Map.put(tree || %{}, to_string(key), value)
  end

  defp put_path(tree, [key | rest], value) do
    key = to_string(key)
    Map.put(tree || %{}, key, put_path(Map.get(tree || %{}, key, %{}), rest, value))
  end

  defp value_at(tree, path) do
    Enum.reduce_while(path, tree, fn segment, acc ->
      case acc do
        %{} -> {:cont, Map.get(acc, to_string(segment))}
        _other -> {:halt, nil}
      end
    end)
  end

  defp path_segments({nil, key}), do: [to_string(key)]
  defp path_segments({section, key}), do: [to_string(section), to_string(key)]
  defp path_segments(path) when is_binary(path), do: [path]

  defp path_segments(path) when is_tuple(path) do
    path |> Tuple.to_list() |> Enum.map(&normalize_segment/1)
  end

  defp path_segments(path) when is_list(path), do: Enum.map(path, &normalize_segment/1)

  defp normalize_segment(segment) when is_integer(segment), do: segment
  defp normalize_segment(segment), do: to_string(segment)

  defp parse_pointer(""), do: []

  defp parse_pointer(pointer) do
    pointer
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.map(&unescape_pointer/1)
    |> Enum.map(&parse_segment/1)
  end

  defp unescape_pointer(segment) do
    segment
    |> String.replace("~1", "/")
    |> String.replace("~0", "~")
  end

  defp parse_segment(segment) do
    case Integer.parse(segment) do
      {integer, ""} -> integer
      _other -> segment
    end
  end
end
