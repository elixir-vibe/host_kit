defmodule HostKit.Secret do
  @moduledoc "References to secrets resolved at HostKit control-plane boundaries."

  @type source ::
          {:env, String.t()} | {:file, String.t()} | {:command, {String.t(), [String.t()]}}
  @type t :: %__MODULE__{source: source()}

  defstruct source: nil

  @spec env(String.t()) :: t()
  def env(name) when is_binary(name), do: %__MODULE__{source: {:env, name}}

  @spec file(String.t()) :: t()
  def file(path) when is_binary(path), do: %__MODULE__{source: {:file, path}}

  @spec command(String.t() | [String.t()] | {String.t(), [String.t()]}) :: t()
  def command(command) when is_binary(command), do: %__MODULE__{source: {:command, {command, []}}}

  def command({command, args}) when is_binary(command) and is_list(args),
    do: %__MODULE__{source: {:command, {command, args}}}

  def command([command | args]) when is_binary(command) and is_list(args),
    do: %__MODULE__{source: {:command, {command, args}}}

  @spec from_opts!(keyword()) :: t() | :redacted
  def from_opts!(opts) do
    case opts do
      [env: :redacted] -> :redacted
      [env: env] when is_binary(env) -> env(env)
      [file: path] when is_binary(path) -> file(path)
      [command: command] -> command(command)
      _other -> raise ArgumentError, "secret requires exactly one of :env, :file, or :command"
    end
  end

  @spec secret?(term()) :: boolean()
  def secret?(%__MODULE__{}), do: true
  def secret?(:redacted), do: true
  def secret?(%{} = map), do: Enum.any?(map, fn {_key, value} -> secret?(value) end)

  def secret?(values) when is_list(values) do
    if Keyword.keyword?(values),
      do: Enum.any?(values, fn {_key, value} -> secret?(value) end),
      else: Enum.any?(values, &secret?/1)
  end

  def secret?(_value), do: false

  @spec resolve(term()) :: {:ok, term()} | {:error, term()}
  def resolve(%__MODULE__{source: {:env, name}}) do
    case System.fetch_env(name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_secret_env, name}}
    end
  end

  def resolve(%__MODULE__{source: {:file, path}}) do
    case File.read(path) do
      {:ok, value} -> {:ok, String.trim_trailing(value, "\n")}
      {:error, reason} -> {:error, {:secret_file_failed, path, reason}}
    end
  end

  def resolve(%__MODULE__{source: {:command, {command, args}}}) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim_trailing(output)}
      {_output, status} -> {:error, {:secret_command_failed, status}}
    end
  rescue
    error in [ErlangError, RuntimeError, ArgumentError] ->
      {:error, {:secret_command_failed, error.__struct__, Exception.message(error)}}
  end

  def resolve(value), do: {:ok, value}

  @spec resolve!(term()) :: term()
  def resolve!(%__MODULE__{source: {:env, name}}), do: System.fetch_env!(name)

  def resolve!(%__MODULE__{source: {:file, path}}) do
    path
    |> File.read!()
    |> String.trim_trailing("\n")
  end

  def resolve!(%__MODULE__{source: {:command, {command, args}}}) do
    case System.cmd(command, args, stderr_to_stdout: true) do
      {output, 0} ->
        String.trim_trailing(output)

      {_output, status} ->
        raise "secret command failed with status #{status}"
    end
  end

  def resolve!(value), do: value
end
