defmodule HostKit.Package.Repology.Client do
  @moduledoc "HTTP client for the Repology API."

  alias HostKit.Package.Repology.{Record, Records}

  @default_base_url "https://repology.org/api/v1"
  @default_site_url "https://repology.org"
  @default_user_agent "host_kit/0.1 (+https://github.com/elixir-vibe/host_kit/issues)"
  @default_timeout 15_000

  @type option ::
          {:base_url, String.t()}
          | {:site_url, String.t()}
          | {:user_agent, String.t()}
          | {:timeout, pos_integer()}
          | {:rate_limit, boolean()}
          | {:req_options, keyword()}

  @type error ::
          {:http_error, non_neg_integer(), term()}
          | {:invalid_response, term()}
          | {:request_error, Exception.t()}
          | JSONCodec.Error.t()
          | Jason.DecodeError.t()

  @spec project(String.t() | atom(), [option()]) :: {:ok, [Record.t()]} | {:error, error()}
  def project(project, opts \\ []) when is_binary(project) or is_atom(project) do
    project = project |> to_string() |> URI.encode()

    :ok = HostKit.Package.Repology.RateLimit.wait(opts)

    opts
    |> request()
    |> Req.get(Keyword.merge(req_options(opts), url: "/project/#{project}"))
    |> decode_response({:list, Record})
  rescue
    error in [Req.TransportError, Req.HTTPError, Jason.DecodeError, JSONCodec.Error] ->
      {:error, normalize_exception(error)}
  end

  @spec project_by_package(String.t(), String.t(), [option()]) ::
          {:ok, [Record.t()]} | {:error, error()}
  def project_by_package(repo, package, opts \\ []) when is_binary(repo) and is_binary(package) do
    query =
      URI.encode_query(%{
        repo: repo,
        name_type: "binname",
        target_page: "api_v1_project",
        name: package
      })

    opts
    |> request(:site)
    |> Req.get(Keyword.merge(req_options(opts), url: "/tools/project-by?#{query}"))
    |> decode_response({:list, Record})
  rescue
    error in [Req.TransportError, Req.HTTPError, Jason.DecodeError, JSONCodec.Error] ->
      {:error, normalize_exception(error)}
  end

  @spec projects(String.t() | nil, [option()]) ::
          {:ok, %{String.t() => [Record.t()]}} | {:error, error()}
  def projects(start \\ nil, opts \\ []) do
    url = if start, do: "/projects/#{URI.encode(start)}/", else: "/projects/"

    :ok = HostKit.Package.Repology.RateLimit.wait(opts)

    opts
    |> request()
    |> Req.get(Keyword.merge(req_options(opts), url: url))
    |> decode_response({:map, :string, {:list, Record}})
  rescue
    error in [Req.TransportError, Req.HTTPError, Jason.DecodeError, JSONCodec.Error] ->
      {:error, normalize_exception(error)}
  end

  @spec package_names(String.t() | atom(), String.t() | Regex.t(), [option()]) ::
          {:ok, [String.t()]} | {:error, error()}
  def package_names(project, repo_match, opts \\ []) do
    with {:ok, records} <- project(project, opts) do
      {:ok, Records.package_names(records, repo_match)}
    end
  end

  defp request(opts, base \\ :api) do
    Req.new(
      base_url: base_url(opts, base),
      receive_timeout: Keyword.get(opts, :timeout, @default_timeout),
      retry: false,
      headers: [
        {"accept", "application/json"},
        {"user-agent", Keyword.get(opts, :user_agent, @default_user_agent)}
      ]
    )
  end

  defp base_url(opts, :api), do: Keyword.get(opts, :base_url, @default_base_url)
  defp base_url(opts, :site), do: Keyword.get(opts, :site_url, @default_site_url)

  defp req_options(opts), do: Keyword.get(opts, :req_options, [])

  defp decode_response({:ok, %Req.Response{status: status, body: body}}, type)
       when status in 200..299 do
    body
    |> decode_body()
    |> JSONCodec.Decoder.decode(type, [], [])
    |> then(&{:ok, &1})
  rescue
    error in [Jason.DecodeError, JSONCodec.Error] -> {:error, error}
  end

  defp decode_response({:ok, %Req.Response{status: status, body: body}}, _type) do
    {:error, {:http_error, status, body}}
  end

  defp decode_response({:error, %{} = error}, _type), do: {:error, normalize_exception(error)}

  defp decode_body(body) when is_binary(body), do: Jason.decode!(body)
  defp decode_body(body), do: body

  defp normalize_exception(%Req.TransportError{} = error), do: {:request_error, error}
  defp normalize_exception(error), do: error
end
