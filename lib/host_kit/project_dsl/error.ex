defmodule HostKit.ProjectDSL.UnknownDefinitionError do
  @moduledoc "Raised when a ProjectDSL defservice defblock contains an unsupported form."

  defexception [:form]

  @impl true
  def message(%__MODULE__{form: form}) do
    """
    unknown ProjectDSL definition: #{form}

    Supported forms inside defservice are:

        let :helper_name, do: expression
        path :helper_dir, root(:root_name), service_name()
        macro :helper_name do
          ...
        end
    """
  end
end

defmodule HostKit.ProjectDSL.UnknownRootError do
  @moduledoc "Raised when a ProjectDSL root lookup references an undefined root."

  defexception [:name, known: [], line: nil]

  @impl true
  def message(%__MODULE__{name: name, known: known, line: line}) do
    """
    unknown ProjectDSL root #{inspect(name)}#{location(line)}

    Known roots: #{inspect(known)}

    Define it before defservice:

        root #{inspect(name)}, "/path"
    """
  end

  defp location(nil), do: ""
  defp location(line), do: " at line #{line}"
end

defmodule HostKit.ProjectDSL.UnknownPrefixError do
  @moduledoc "Raised when a ProjectDSL prefix lookup references an undefined prefix."

  defexception [:name, known: [], line: nil]

  @impl true
  def message(%__MODULE__{name: name, known: known, line: line}) do
    """
    unknown ProjectDSL prefix #{inspect(name)}#{location(line)}

    Known prefixes: #{inspect(known)}

    Define it before defservice:

        prefix #{inspect(name)}, "value-"
    """
  end

  defp location(nil), do: ""
  defp location(line), do: " at line #{line}"
end
