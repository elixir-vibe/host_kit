defmodule HostKit.Env do
  @moduledoc "Rendering for HostKit env files."

  alias HostKit.Resources.EnvFile

  @spec public_entries(EnvFile.t()) :: %{String.t() => String.t()}
  def public_entries(%EnvFile{entries: entries}) do
    entries
    |> Enum.flat_map(fn
      {:set, key, value} -> [{key, to_string(value)}]
      {:secret, _key, _secret} -> []
    end)
    |> Map.new()
  end

  @spec secret_paths(EnvFile.t()) :: [String.t()]
  def secret_paths(%EnvFile{entries: entries}) do
    entries
    |> Enum.flat_map(fn
      {:secret, key, _secret} -> [key]
      _entry -> []
    end)
    |> Enum.sort()
  end

  @spec public_entries_from_content(String.t(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def public_entries_from_content(content, keys) do
    with {:ok, entries} <- parse(content) do
      {:ok, Map.take(entries, keys)}
    end
  end

  @spec render(EnvFile.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(%EnvFile{} = env_file, opts \\ []) do
    with {:ok, lines} <- render_entries(env_file.entries, opts) do
      content = IO.iodata_to_binary([Enum.intersperse(lines, "\n"), "\n"])
      validate_dotenv(content)
    end
  end

  defp render_entries(entries, opts) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, lines} ->
      case render_entry(entry, opts) do
        {:ok, line} -> {:cont, {:ok, [line | lines]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp render_entry({:set, key, value}, _opts), do: {:ok, "#{key}=#{quote_value(value)}"}

  defp render_entry({:secret, _key, :redacted}, _opts),
    do: {:error, :redacted_secret_not_renderable}

  defp render_entry({:secret, key, %HostKit.Secret{} = secret}, _opts) do
    {:ok, "#{key}=#{quote_value(HostKit.Secret.resolve!(secret))}"}
  rescue
    error in [System.EnvError] -> {:error, {:missing_secret_env, error.env}}
  end

  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(content) do
    path = Path.join(System.tmp_dir!(), "host-kit-env-#{System.unique_integer([:positive])}.env")

    try do
      File.write!(path, content)
      Dotenvy.source(path, side_effect: fn _env -> :ok end)
    after
      File.rm(path)
    end
  end

  defp validate_dotenv(content) do
    case parse(content) do
      {:ok, _env} -> {:ok, content}
      {:error, reason} -> {:error, {:invalid_env_file, reason}}
    end
  end

  defp quote_value(value) do
    value
    |> to_string()
    |> String.replace("\\", "\\\\")
    |> String.replace("\n", "\\n")
    |> String.replace("\"", "\\\"")
    |> then(&"\"#{&1}\"")
  end
end
