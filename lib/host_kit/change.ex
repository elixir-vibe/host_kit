defmodule HostKit.Change do
  @moduledoc "A planned change for one HostKit resource."

  alias HostKit.Addr.Resource

  @type action :: :create | :update | :delete | :no_op | :read
  @type t :: %__MODULE__{
          action: action(),
          resource_id: Resource.t() | term(),
          before: struct() | nil,
          after: struct() | nil,
          reason: String.t() | atom() | nil,
          diff: HostKit.Diff.t() | nil
        }

  defstruct action: nil,
            resource_id: nil,
            before: nil,
            after: nil,
            reason: nil,
            diff: nil

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%HostKit.Change{} = change, _opts) do
      concat(["#HostKit.Change<", summary(change), ">"])
    end

    defp summary(change) do
      [
        to_string(change.action || :unknown),
        " ",
        format_resource_id(change.resource_id),
        format_reason(change.reason)
      ]
      |> IO.iodata_to_binary()
    end

    defp format_resource_id(%HostKit.Addr.Resource{} = resource), do: to_string(resource)
    defp format_resource_id({type, name}), do: "#{type}.#{name}"
    defp format_resource_id(resource_id), do: inspect(resource_id)

    defp format_reason(nil), do: ""
    defp format_reason(reason), do: " " <> HostKit.Error.format(reason, max: 160)
  end
end
