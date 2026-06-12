defmodule Mix.Tasks.HostKit.Dump do
  @moduledoc "Dumps a HostKit project as inspectable Elixir structs."

  use Mix.Task

  @shortdoc "Dump HostKit project structs"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    path = List.first(args) || "infra/config.exs"
    project = HostKit.load!(path)
    IO.inspect(project, pretty: true, limit: :infinity, structs: true)
  end
end
