defmodule Hakushi.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hattoriai/hakushi"

  # HAKUSHI_OLDEST=1 resolves the oldest Phoenix and LiveView that Hakushi
  # supports, for the CI job that tests them.
  @oldest System.get_env("HAKUSHI_OLDEST") in ["1", "true"]

  def project do
    [
      app: :hakushi,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      # For the code reloader of the development server (dev.exs). The
      # listener is Phoenix 1.8's, so the oldest versions go without it.
      listeners: if(@oldest, do: [], else: [Phoenix.CodeReloader]),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit, :esbuild, :ecto],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"},
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Hakushi",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [mod: {Hakushi.Application, []}, extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bandit, "~> 1.5", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # A canvas kept in a column of the app's database (Hakushi.Graph.Type)
      # needs Ecto; the rest of Hakushi does not.
      {:ecto, "~> 3.13", optional: true},
      {:esbuild, "~> 0.10", only: :dev, runtime: false},
      # Shared canvases (`live`): Issho is the room, its people and their
      # cursors. A canvas without `live` never needs it.
      # Until Issho 0.2 is on Hex.
      {:issho, github: "hattoriai/issho", branch: "main", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:lazy_html, "~> 0.1", only: :test},
      {:phoenix, if(@oldest, do: "~> 1.7.14", else: "~> 1.7.14 or ~> 1.8")},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, if(@oldest, do: "~> 1.1.0", else: "~> 1.1")},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp description do
    "Canvas for Phoenix: nodes of your own HEEx on an endless sheet, joined by edges, " <>
      "with every change checked on the server and live collaboration."
  end

  defp package do
    [
      name: "hakushi",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      # The bundle files by name: other build output in priv/static never
      # goes into the package.
      files: ~w(
        lib
        priv/static/hakushi.esm.js
        priv/static/hakushi.cjs.js
        priv/static/hakushi.css
        priv/static/hakushi-sumi.css
        package.json
        mix.exs
        .formatter.exs
        guides
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      # The banner of the README, at the same relative path in the docs.
      assets: %{"media" => "media"},
      extras: [
        "README.md",
        "guides/quickstart.md",
        "guides/nodes.md",
        "guides/edges.md",
        "guides/groups.md",
        "guides/layout.md",
        "guides/changes.md",
        "guides/collaboration.md",
        "guides/navigation.md",
        "guides/testing.md",
        "guides/theming.md",
        "guides/accessibility.md",
        "guides/limits.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/quickstart.md",
          "guides/nodes.md",
          "guides/edges.md",
          "guides/groups.md",
          "guides/layout.md",
          "guides/changes.md",
          "guides/collaboration.md",
          "guides/navigation.md",
          "guides/testing.md",
          "guides/theming.md"
        ],
        Reference: [
          "guides/accessibility.md",
          "guides/limits.md"
        ]
      ],
      groups_for_modules: [
        Canvas: [Hakushi, Hakushi.Components, Hakushi.Canvas, Hakushi.Live, Hakushi.Messages],
        Graph: [Hakushi.Graph, Hakushi.Node, Hakushi.Edge, Hakushi.Change, Hakushi.Rules],
        Collaboration: [Hakushi.Room],
        Storage: [Hakushi.Graph.Type],
        Testing: [Hakushi.Test]
      ]
    ]
  end

  # The browser tests need their npm packages; `npm ci` runs once.
  defp e2e_deps(_args) do
    unless File.dir?("e2e/node_modules") do
      Mix.Task.run("cmd", ~w(--cd e2e npm ci))
    end
  end

  defp aliases do
    [
      setup: ["deps.get", "cmd --cd assets npm ci", "cmd --cd e2e npm ci"],
      "assets.build": ["hakushi.build"],
      dev: "run --no-halt dev.exs",
      "test.e2e": [&e2e_deps/1, "cmd --cd e2e npm test"],
      "test.js": ["cmd --cd assets npm test"],
      # The compile and the asset build run in a child VM, as in Kotoba and
      # Koyomi: once anything compiles in this VM, Mix no longer finds the
      # tasks of the Hex archive. The check refuses a priv/static with
      # anything but the bundle files.
      release: [
        "cmd mix hakushi.build",
        "cmd mix hakushi.release_check",
        "hex.publish --yes",
        "cmd git tag v#{@version} -f",
        "cmd git push",
        "cmd git push --tags"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
