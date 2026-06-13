defmodule HostKit.Env do
  @moduledoc "Rendering for HostKit env files."

  alias HostKit.Resources.EnvFile

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

  defp render_entry({:secret, key, {:env, env_name}}, _opts) do
    case System.fetch_env(env_name) do
      {:ok, value} -> {:ok, "#{key}=#{quote_value(value)}"}
      :error -> {:error, {:missing_secret_env, env_name}}
    end
  end

  defp validate_dotenv(content) do
    path = Path.join(System.tmp_dir!(), "host-kit-env-#{System.unique_integer([:positive])}.env")

    try do
      File.write!(path, content)

      case Dotenvy.source(path, side_effect: fn _env -> :ok end) do
        {:ok, _env} -> {:ok, content}
        {:error, reason} -> {:error, {:invalid_env_file, reason}}
      end
    after
      File.rm(path)
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
