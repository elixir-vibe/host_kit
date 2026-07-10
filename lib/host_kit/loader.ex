# Config evaluation is intentionally normalized at this boundary.
# reach:disable-for-this-file bare_rescue
defmodule HostKit.Loader do
  @moduledoc "Loads HostKit `.exs` project declarations."

  alias HostKit.Project

  @spec load(Path.t(), keyword()) :: {:ok, Project.t()} | {:error, term()}
  def load(path, opts \\ []) do
    path = Path.expand(path)

    try do
      require_files(path, Keyword.get(opts, :require, []))
      {project, _binding} = Code.eval_file(path)

      case project do
        %Project{} -> {:ok, project}
        other -> {:error, {:expected_project, other}}
      end
    rescue
      exception -> {:error, {exception, __STACKTRACE__}}
    end
  end

  defp require_files(path, files) do
    base = Path.dirname(path)

    files
    |> List.wrap()
    |> Enum.map(&Path.expand(&1, base))
    |> Enum.each(&Code.require_file/1)
  end
end
