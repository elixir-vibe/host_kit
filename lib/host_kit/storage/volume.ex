defmodule HostKit.Storage.Volume do
  @moduledoc "Named storage volume metadata."

  @type t :: %__MODULE__{
          name: atom(),
          path: String.t(),
          owner: String.t() | nil,
          group: String.t() | nil,
          mode: non_neg_integer() | nil,
          writable: boolean(),
          backup: boolean(),
          secret: boolean(),
          mount_path: String.t() | nil,
          meta: map()
        }

  defstruct name: nil,
            path: nil,
            owner: nil,
            group: nil,
            mode: nil,
            writable: true,
            backup: false,
            secret: false,
            mount_path: nil,
            meta: %{}
end
