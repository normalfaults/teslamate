defmodule TeslaMateWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :teslamate

  socket "/live", TeslaMateWeb.LiveViewSocket

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :teslamate,
    gzip: false,
    only:
      ~w(css fonts images js favicon.ico robots.txt android-chrome-192x192.png android-chrome-512x512.png apple-touch-icon.png browserconfig.xml favicon-16x16.png favicon-32x32.png mstile-150x150.png safari-pinned-tab.svg site.webmanifest)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session,
    store: :cookie,
    key: "_teslamate_key",
    signing_salt: "yt5O3CAQ"

  plug TeslaMateWeb.Router
end
