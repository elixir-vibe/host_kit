defmodule HostKit.Caddy.JSON.Config do
  @moduledoc "Caddy JSON config root."

  use JSONCodec

  alias HostKit.Caddy.JSON.Apps

  defstruct apps: %Apps{}

  @type t :: %__MODULE__{apps: Apps.t()}
end
