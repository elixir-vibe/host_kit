defmodule HelloPhoenixWeb.HealthController do
  use HelloPhoenixWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
