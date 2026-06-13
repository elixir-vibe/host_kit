defmodule HostKit.Package.Lock do
  @moduledoc "JSON lock file for resolved target package names."

  @type t :: %__MODULE__{
          target: String.t() | nil,
          packages: %{String.t() => String.t()}
        }

  defstruct target: nil, packages: %{}

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, map} <- Jason.decode(content) do
      from_map(map)
    end
  rescue
    error in [Jason.DecodeError, JSONCodec.Error] -> {:error, error}
  end

  @spec save(Path.t(), t()) :: :ok | {:error, term()}
  def save(path, %__MODULE__{} = lock) do
    content = lock |> to_map() |> Jason.encode_to_iodata!(pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, [content, ?\n])
    end
  end

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    {:ok,
     %__MODULE__{
       target: decode(Map.get(map, "target"), {:nullable, :string}, [:target]),
       packages: decode(Map.get(map, "packages", %{}), {:map, :string, :string}, [:packages])
     }}
  rescue
    error in [JSONCodec.Error] -> {:error, error}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = lock) do
    %{"target" => lock.target, "packages" => lock.packages}
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
    %{lock | target: target, packages: Map.put(lock.packages, to_string(name), package)}
  end

  defp decode(value, type, path), do: JSONCodec.Decoder.decode(value, type, path, [])

  defp target_match?(target, repo) when is_binary(target) and is_binary(repo), do: target == repo
  defp target_match?(_target, %Regex{}), do: false
  defp target_match?(_target, _repo), do: false
end
