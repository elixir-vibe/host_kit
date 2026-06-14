defmodule HostKit.Case do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      use ExUnit.Case, unquote(opts)

      import HostKit.Case, only: [fixture_path: 1]
    end
  end

  def fixture_path(path) when is_binary(path) do
    Path.expand(Path.join(["test", "fixtures", path]), File.cwd!())
  end
end
