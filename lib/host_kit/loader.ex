defmodule HostKit.Loader do
  @moduledoc "Loads HostKit `.exs` project declarations."

  alias HostKit.Project

  @spec load(Path.t(), keyword()) :: {:ok, Project.t()} | {:error, term()}
  def load(path, _opts \\ []) do
    path = Path.expand(path)

    try do
      {project, _binding} = Code.eval_file(path)

      case project do
        %Project{} -> {:ok, project}
        other -> {:error, {:expected_project, other}}
      end
    rescue
      exception -> {:error, {exception, __STACKTRACE__}}
    end
  end
end
