defmodule Mix.Tasks.HostKit.Dump do
  @moduledoc "Dumps a HostKit project as inspectable Elixir structs."

  use Mix.Task

  @shortdoc "Dump HostKit project structs"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} = OptionParser.parse!(args, strict: [require: :keep])
    path = List.first(positional) || "infra/config.exs"
    project = HostKit.load!(path, require: Keyword.get_values(opts, :require))
    project |> inspect(pretty: true, limit: :infinity, structs: true) |> IO.puts()
  end
end
