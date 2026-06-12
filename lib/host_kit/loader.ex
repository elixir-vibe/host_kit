defmodule HostKit.Loader do
  @moduledoc "Loads HostKit `.exs` project declarations."

  alias HostKit.Project

  @spec load(Path.t(), keyword()) :: {:ok, Project.t()} | {:error, term()}
  def load(path, _opts \\ []) do
    path = Path.expand(path)

    try do
      require_project_support_files(path)
      {project, _binding} = Code.eval_file(path)

      case project do
        %Project{} -> {:ok, project}
        other -> {:error, {:expected_project, other}}
      end
    rescue
      exception in [ArgumentError, Code.LoadError, CompileError, RuntimeError, SyntaxError] ->
        {:error, {exception, __STACKTRACE__}}
    end
  end

  defp require_project_support_files(path) do
    path
    |> Path.dirname()
    |> Path.join("*_infra.exs")
    |> Path.wildcard()
    |> Enum.reject(&(&1 == path))
    |> Enum.each(&Code.require_file/1)
  end
end
