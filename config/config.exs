import Config

if config_env() == :dev do
  # The canvas bundles. NODE_PATH is unset: the bundles never pick up a
  # package from deps/.
  esbuild_args = ~w(
    src/index.ts
    --bundle
    --minify
    --target=es2020
    --external:phoenix
    --external:phoenix_live_view
  )

  config :esbuild,
    version: "0.28.2",
    hakushi_esm: [
      args: esbuild_args ++ ~w(--format=esm --outfile=../priv/static/hakushi.esm.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    hakushi_cjs: [
      args: esbuild_args ++ ~w(--format=cjs --outfile=../priv/static/hakushi.cjs.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    # Issho's browser client, from its sources while Hakushi takes Issho
    # from GitHub (its Hex package has it built), with Issho's own
    # arguments: for `mix dev` and the browser tests.
    issho_client: [
      args:
        ~w(src/index.ts --bundle --minify --target=es2020 --external:phoenix --format=esm --outfile=../priv/static/issho.esm.js),
      cd: Path.expand("../deps/issho/assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ]
end

if config_env() == :test do
  config :logger, level: :warning
  config :phoenix, :json_library, JSON

  config :hakushi, HakushiTest.Endpoint,
    secret_key_base: String.duplicate("hakushi-test-secret-key-base-", 4),
    live_view: [signing_salt: "hakushi-test-salt"],
    pubsub_server: HakushiTest.PubSub,
    render_errors: [formats: [html: HakushiTest.ErrorHTML], layout: false],
    server: false
end
