defmodule HostKit.Sigils do
  @moduledoc "HostKit command and shell sigils."

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
end
