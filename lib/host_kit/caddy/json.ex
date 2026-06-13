defmodule HostKit.Caddy.JSON do
  @moduledoc "Builds Caddy JSON config structs from HostKit Caddy resources."

  alias HostKit.Caddy.Directive.{Encode, FileServer, ReverseProxy, Root}
  alias HostKit.Caddy.JSON

  @spec config_for_sites([HostKit.Caddy.Site.t()]) :: JSON.Config.t()
  def config_for_sites(sites) do
    %JSON.Config{
      apps: %JSON.Apps{
        http: %JSON.HTTP{
          servers: %{
            "srv0" => %JSON.Server{
              listen: [":443"],
              routes: Enum.map(sites, &route_for_site/1),
              logs: logs_for_sites(sites)
            }
          }
        }
      }
    }
  end

  @spec route_for_site(HostKit.Caddy.Site.t()) :: JSON.Route.t()
  def route_for_site(site) do
    %JSON.Route{
      match: [%JSON.Match.Host{host: [site.host]}],
      handle: [%JSON.Handler.Subroute{routes: [%JSON.Route{handle: handlers_for(site)}]}],
      terminal: true
    }
  end

  @spec to_map(struct()) :: map()
  def to_map(struct), do: JSONCodec.to_map(struct)

  @spec encode!(struct(), keyword()) :: String.t()
  def encode!(struct, opts \\ [pretty: true]), do: struct |> to_map() |> Jason.encode!(opts)

  defp logs_for_sites(sites) do
    if Enum.any?(sites, &(get_in(&1.meta, [:logs, :driver]) == :caddy_access)) do
      %{default_logger_name: "hostkit_caddy_access"}
    end
  end

  defp handlers_for(site) do
    site.directives
    |> Enum.flat_map(&handler_for_directive/1)
  end

  defp handler_for_directive(%Root{path: path}), do: [%JSON.Handler.Vars{root: path}]

  defp handler_for_directive(%Encode{formats: formats}) do
    encodings = Map.new(formats, &{to_string(&1), %{}})
    [%JSON.Handler.Encode{encodings: encodings}]
  end

  defp handler_for_directive(%FileServer{browse: false}), do: [%JSON.Handler.FileServer{}]

  defp handler_for_directive(%FileServer{browse: true}),
    do: [%JSON.Handler.FileServer{browse: %{}}]

  defp handler_for_directive(%ReverseProxy{upstreams: upstreams}) do
    [%JSON.Handler.ReverseProxy{upstreams: Enum.map(upstreams, &%JSON.Upstream{dial: &1})}]
  end
end
