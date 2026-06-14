defmodule Mix.Tasks.HostKit.Down do
  @moduledoc """
  Builds a down/rollback plan from an existing HostKit plan artifact.

  Rollback is just another plan: inspect the generated down plan, save it if you
  want, then apply it with `mix host_kit.apply --plan down.plan.json --confirm`.
  """

  use Mix.Task

  @shortdoc "Build a HostKit down plan"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional} =
      OptionParser.parse!(args,
        strict: [
          plan: :string,
          out: :string,
          format: :string,
          only: :keep,
          except: :keep
        ]
      )

    path =
      Keyword.get(opts, :plan) || List.first(positional) || Mix.raise("expected a plan artifact")

    with {:ok, plan} <- HostKit.Plan.Artifact.load(path),
         {:ok, down_plan} <- HostKit.down(plan, down_opts(opts)) do
      maybe_write_artifact(down_plan, opts)
      IO.puts(Mix.Tasks.HostKit.Output.format_plan(down_plan, opts))
    else
      {:error, reason} -> Mix.raise("could not build HostKit down plan: #{inspect(reason)}")
    end
  end

  defp down_opts(opts) do
    []
    |> put_filter(:only, Keyword.get_values(opts, :only))
    |> put_filter(:except, Keyword.get_values(opts, :except))
  end

  defp put_filter(opts, _key, []), do: opts

  defp put_filter(opts, key, values),
    do: Keyword.put(opts, key, Enum.map(values, &parse_resource_id/1))

  defp parse_resource_id(resource) do
    case String.split(resource, ":", parts: 2) do
      [type, name] -> {resource_type(type), name}
      _ -> Mix.raise("invalid resource id #{inspect(resource)}, expected type:name")
    end
  end

  defp resource_type(type) do
    String.to_existing_atom(type)
  rescue
    ArgumentError -> Mix.raise("unknown resource type: #{inspect(type)}")
  end

  defp maybe_write_artifact(plan, opts) do
    case Keyword.get(opts, :out) do
      nil ->
        :ok

      path ->
        case HostKit.Plan.Artifact.save(path, plan) do
          :ok ->
            :ok

          {:error, reason} ->
            Mix.raise("could not write HostKit down plan artifact: #{inspect(reason)}")
        end
    end
  end
end
