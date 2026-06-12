defmodule HostKit.Addr.AbsResource do
  @moduledoc "Resource address with module/service path context."

  alias HostKit.Addr.Resource

  @type t :: %__MODULE__{module: [atom()], resource: Resource.t()}

  defstruct module: [:root], resource: nil

  @spec new([atom()], Resource.t()) :: t()
  def new(module, %Resource{} = resource) when is_list(module) do
    %__MODULE__{module: module, resource: resource}
  end

  defimpl String.Chars do
    def to_string(%{module: [:root], resource: resource}), do: Kernel.to_string(resource)

    def to_string(%{module: module, resource: resource}) do
      module_path =
        module |> Enum.reject(&(&1 == :root)) |> Enum.map_join(".", &Kernel.to_string/1)

      "module.#{module_path}.#{resource}"
    end
  end
end
