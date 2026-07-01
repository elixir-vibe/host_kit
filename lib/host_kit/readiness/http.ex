defmodule HostKit.Readiness.HTTP do
  @moduledoc "HTTP readiness check."

  @type url :: String.t() | HostKit.Endpoint.t()

  @type t :: %__MODULE__{
          url: url(),
          path: String.t() | nil,
          expect_status: pos_integer(),
          expect_body: String.t() | nil
        }

  defstruct [:url, :path, expect_status: 200, expect_body: nil]

  @spec new(url(), keyword()) :: t()
  def new(url, opts \\ []) do
    %__MODULE__{
      url: url,
      path: Keyword.get(opts, :path),
      expect_status: Keyword.get(opts, :expect_status, Keyword.get(opts, :status, 200)),
      expect_body: Keyword.get(opts, :expect_body, Keyword.get(opts, :body))
    }
  end

  @spec url(t()) :: String.t()
  def url(%__MODULE__{url: %HostKit.Endpoint{} = endpoint, path: path}) do
    endpoint |> HostKit.Endpoint.url() |> append_path(path)
  end

  def url(%__MODULE__{url: url, path: path}) when is_binary(url), do: append_path(url, path)

  defp append_path(url, nil), do: url
  defp append_path(url, ""), do: url
  defp append_path(url, "/" <> _ = path), do: url <> path
  defp append_path(url, path), do: url <> "/" <> path
end
