defmodule HostKit.Readiness.HTTP do
  @moduledoc "HTTP readiness check."

  @type t :: %__MODULE__{
          url: String.t(),
          expect_status: pos_integer(),
          expect_body: String.t() | nil
        }

  defstruct [:url, expect_status: 200, expect_body: nil]

  @spec new(String.t(), keyword()) :: t()
  def new(url, opts \\ []) do
    %__MODULE__{
      url: url,
      expect_status: Keyword.get(opts, :expect_status, Keyword.get(opts, :status, 200)),
      expect_body: Keyword.get(opts, :expect_body, Keyword.get(opts, :body))
    }
  end
end
