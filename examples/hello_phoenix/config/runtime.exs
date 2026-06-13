import Config

if config_env() == :prod do
  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")

  config :hello_phoenix, HelloPhoenixWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {127, 0, 0, 1}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
