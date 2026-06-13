import Config

config :hello_phoenix, HelloPhoenixWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [html: HelloPhoenixWeb.ErrorHTML, json: HelloPhoenixWeb.ErrorJSON]],
  pubsub_server: HelloPhoenix.PubSub,
  live_view: [signing_salt: "hostkit-demo"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
