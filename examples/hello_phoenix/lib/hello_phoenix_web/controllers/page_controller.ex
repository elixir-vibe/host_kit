defmodule HelloPhoenixWeb.PageController do
  use HelloPhoenixWeb, :controller

  def home(conn, _params) do
    html(conn, """
    <!doctype html>
    <html>
      <head><meta charset=\"utf-8\"><title>Hello Phoenix from HostKit</title></head>
      <body>
        <h1>Hello Phoenix from HostKit</h1>
        <p>This Phoenix release was deployed by HostKit.</p>
      </body>
    </html>
    """)
  end
end
