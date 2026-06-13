defmodule HostKit.Plan.Artifact do
  @moduledoc "Portable JSON artifact for a resolved HostKit plan."

  use JSONCodec, fast_path: :json

  alias HostKit.Plan

  @version 1

  defstruct version: @version,
            target: nil,
            plan: nil

  @type t :: %__MODULE__{
          version: pos_integer(),
          target: String.t() | nil,
          plan: String.t()
        }

  codec(:version, transform: :validate_version!)

  @spec from_plan(Plan.t(), keyword()) :: t()
  def from_plan(%Plan{} = plan, opts \\ []) do
    %__MODULE__{
      target: Keyword.get(opts, :target),
      plan: encode_plan(plan)
    }
  end

  @spec to_plan(t()) :: {:ok, Plan.t()} | {:error, term()}
  def to_plan(%__MODULE__{plan: encoded}) when is_binary(encoded) do
    with {:ok, binary} <- Base.url_decode64(encoded, padding: false) do
      case :erlang.binary_to_term(binary, [:safe]) do
        %Plan{} = plan -> {:ok, plan}
        other -> {:error, {:invalid_plan_artifact_payload, other}}
      end
    end
  rescue
    ArgumentError -> {:error, :invalid_plan_artifact_payload}
  end

  def to_plan(%__MODULE__{}), do: {:error, :invalid_plan_artifact_payload}

  @spec load(Path.t()) :: {:ok, Plan.t()} | {:error, term()}
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, artifact} <- decode(content) do
      to_plan(artifact)
    end
  end

  @spec save(Path.t(), Plan.t(), keyword()) :: :ok | {:error, term()}
  def save(path, %Plan{} = plan, opts \\ []) do
    content = plan |> from_plan(opts) |> dump() |> Jason.encode_to_iodata!(pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, [content, ?\n])
    end
  end

  def validate_version!(@version), do: @version

  def validate_version!(version) do
    raise JSONCodec.Error,
      path: [:version],
      expected: @version,
      got: version,
      reason: :unsupported_plan_artifact_version
  end

  defp encode_plan(%Plan{} = plan) do
    plan
    |> Map.replace!(:opts, [])
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end
end
