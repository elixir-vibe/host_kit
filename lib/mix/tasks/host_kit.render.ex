defmodule Mix.Tasks.HostKit.Render do
  @moduledoc "Renders a HostKit resource by kind and name."

  use Mix.Task

  @shortdoc "Render one HostKit resource"

  @impl true
  def run([path, kind, name]) do
    Mix.Task.run("app.start")

    project = HostKit.load!(path)
    id = {String.to_existing_atom(kind), name}

    case HostKit.Render.render(project, id) do
      {:ok, iodata} -> IO.write(iodata)
      {:error, reason} -> Mix.raise("could not render #{inspect(id)}: #{inspect(reason)}")
    end
  end

  def run(_args) do
    Mix.raise("usage: mix host_kit.render PATH KIND NAME")
  end
end
