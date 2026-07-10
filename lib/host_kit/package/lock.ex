defmodule HostKit.Package.Lock do
  @moduledoc "JSON lock file for resolved target package names."

  use JSONCodec, fast_path: :json

  @version 1

  defstruct version: @version, target: nil, packages: %{}

  @type t :: %__MODULE__{
          version: pos_integer(),
          target: String.t() | nil,
          packages: %{String.t() => String.t()}
        }

  codec(:version, transform: :validate_version!)

  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    case File.read(path) do
      {:ok, content} -> decode(content)
      {:error, reason} -> {:error, reason}
    end
  end

  @spec load!(Path.t()) :: t()
  def load!(path) do
    case load(path) do
      {:ok, lock} -> lock
      {:error, reason} -> raise ArgumentError, "could not load package lock: #{inspect(reason)}"
    end
  end

  @spec save(Path.t(), t()) :: :ok | {:error, term()}
  def save(path, %__MODULE__{} = lock) do
    content = lock |> dump() |> Jason.encode_to_iodata!(pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      HostKit.Runner.Files.write_file(path, [content, ?\n], mode: 0o644)
    end
  end

  @spec get(t(), atom() | String.t(), String.t() | Regex.t()) ::
          {:ok, String.t()} | :error | {:error, term()}
  def get(%__MODULE__{target: target, packages: packages}, name, repo) do
    with :ok <- target_match(target, repo) do
      case Map.fetch(packages, to_string(name)) do
        {:ok, package} when is_binary(package) -> {:ok, package}
        _missing -> :error
      end
    end
  end

  @spec put(t(), atom() | String.t(), String.t(), String.t()) :: t()
  def put(%__MODULE__{} = lock, name, package, target) do
    %{lock | target: target, packages: Map.put(lock.packages, to_string(name), package)}
  end

  def validate_version!(@version), do: @version

  def validate_version!(version) do
    raise JSONCodec.Error,
      path: [:version],
      expected: @version,
      got: version,
      reason: :unsupported_package_lock_version
  end

  defp target_match(target, repo) when is_binary(target) and is_binary(repo) do
    if target == repo, do: :ok, else: {:error, {:package_lock_target_mismatch, target, repo}}
  end

  defp target_match(_target, %Regex{}), do: :ok
  defp target_match(_target, _repo), do: :ok
end
