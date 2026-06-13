defmodule HostKit.Package.Lock do
  @moduledoc "JSON lock file for resolved target package names."

  use JSONCodec, fast_path: :json

  @type t :: %__MODULE__{
          target: String.t() | nil,
          packages: %{String.t() => String.t()}
        }

  defstruct target: nil, packages: nil

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    case File.read(path) do
      {:ok, content} -> decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec save(Path.t(), t()) :: :ok | {:error, term()}
  def save(path, %__MODULE__{} = lock) do
    content = lock |> dump() |> Jason.encode_to_iodata!(pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, [content, ?\n])
    end
  end

  @spec get(t(), atom() | String.t(), String.t() | Regex.t()) :: {:ok, String.t()} | :error
  def get(%__MODULE__{target: target, packages: packages}, name, repo) do
    if target_match?(target, repo) do
      case Map.fetch(packages, to_string(name)) do
        {:ok, package} when is_binary(package) -> {:ok, package}
        _missing -> :error
      end
    else
      :error
    end
  end

  @spec put(t(), atom() | String.t(), String.t(), String.t()) :: t()
  def put(%__MODULE__{} = lock, name, package, target) do
    %{lock | target: target, packages: Map.put(lock.packages || %{}, to_string(name), package)}
  end

  defp target_match?(target, repo) when is_binary(target) and is_binary(repo), do: target == repo
  defp target_match?(_target, %Regex{}), do: false
  defp target_match?(_target, _repo), do: false
end
