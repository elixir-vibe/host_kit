defmodule HostKit.Sigils do
  @moduledoc "HostKit command and shell sigils/macros."

  @doc """
  Parses a Bash script with escaped interpolation.

      bash "rm -rf \#{path} && mkdir -p \#{path}"

  Static `~BASH` remains available when interpolation is not needed.
  """
  defmacro bash(source) do
    quote do
      HostKit.ShellScript.parse!(unquote(escaped_interpolation(source)))
    end
  end

  defmacro sigil_SH({:<<>>, _meta, [source]}, _modifiers) when is_binary(source) do
    command_line = Macro.escape(HostKit.CommandLine.parse!(source))

    quote do
      unquote(command_line)
    end
  end

  defmacro sigil_SH(source, _modifiers) do
    quote do
      HostKit.CommandLine.parse!(unquote(source))
    end
  end

  defmacro sigil_BASH({:<<>>, _meta, [source]}, _modifiers) when is_binary(source) do
    script = Macro.escape(HostKit.ShellScript.parse!(source))

    quote do
      unquote(script)
    end
  end

  defmacro sigil_BASH(source, _modifiers) do
    quote do
      HostKit.ShellScript.parse!(unquote(source))
    end
  end

  defp escaped_interpolation({:<<>>, meta, parts}) do
    {:<<>>, meta, Enum.map(parts, &escape_part/1)}
  end

  defp escaped_interpolation(source), do: source

  defp escape_part({:"::", meta, [{{:., _, [Kernel, :to_string]}, _call_meta, [expr]}, type]}) do
    escaped =
      quote do
        unquote(expr)
        |> to_string()
        |> HostKit.Shell.escape()
      end

    {:"::", meta, [escaped, type]}
  end

  defp escape_part(part), do: part
end
