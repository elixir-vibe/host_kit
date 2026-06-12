defmodule Mix.Tasks.HostKit.Render do
  @moduledoc "Renders a HostKit resource by kind and name."

  use Mix.Task

  @shortdoc "Render one HostKit resource"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} = OptionParser.parse!(args, strict: [require: :keep])

    case positional do
      [path, kind, name] -> render(path, kind, name, opts)
      _args -> Mix.raise("usage: mix host_kit.render [--require FILE] PATH KIND NAME")
    end
  end

  defp render(path, kind, name, opts) do
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))
    id = {String.to_existing_atom(kind), name}

    case HostKit.Render.render(project, id) do
      {:ok, iodata} -> IO.write(iodata)
      {:error, reason} -> Mix.raise("could not render #{inspect(id)}: #{inspect(reason)}")
    end
  end
end
