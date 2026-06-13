defmodule HelloPhoenixWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :hello_phoenix

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(HelloPhoenixWeb.Router)
end
