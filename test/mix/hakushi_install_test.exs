defmodule Mix.Tasks.Hakushi.InstallTest do
  # The task with Igniter, on a project Igniter keeps in memory. The edits
  # themselves are tested in Hakushi.Install.EditsTest, and the task without
  # Igniter in Hakushi.InstallTest.
  use ExUnit.Case, async: true

  import Igniter.Test

  @app_js """
  import {Socket} from "phoenix"
  import {LiveSocket} from "phoenix_live_view"
  import {hooks as colocatedHooks} from "phoenix-colocated/test"

  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
  const liveSocket = new LiveSocket("/live", Socket, {
    params: {_csrf_token: csrfToken},
    hooks: {...colocatedHooks},
  })
  """

  @app_css """
  @import "tailwindcss" source(none);
  @source "../js";
  """

  @config_exs ~S"""
  import Config

  config :esbuild,
    version: "0.25.4",
    test: [
      args: ~w(js/app.js --bundle --outdir=../priv/static/assets/js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
    ]
  """

  @web """
  defmodule TestWeb do
    def html do
      quote do
        use Phoenix.Component
        unquote(html_helpers())
      end
    end

    defp html_helpers do
      quote do
        use Gettext, backend: TestWeb.Gettext
        import Phoenix.HTML
        import TestWeb.CoreComponents
        alias Phoenix.LiveView.JS
        unquote(verified_routes())
      end
    end

    def verified_routes do
      quote do
      end
    end
  end
  """

  defp project(files \\ %{}) do
    test_project(
      files:
        Map.merge(
          %{
            "assets/js/app.js" => @app_js,
            "assets/css/app.css" => @app_css,
            "config/config.exs" => @config_exs,
            "lib/test_web.ex" => @web
          },
          files
        )
    )
  end

  defp install(igniter), do: Igniter.compose_task(igniter, "hakushi.install", [])

  defp content(igniter, path),
    do: igniter.rewrite |> Rewrite.source!(path) |> Rewrite.Source.get(:content)

  test "adds the hook, the style sheet and the components" do
    igniter = project() |> install()

    assert content(igniter, "assets/js/app.js") =~ ~s(import { Hakushi } from "hakushi")
    assert content(igniter, "assets/js/app.js") =~ "hooks: {...colocatedHooks, Hakushi},"

    assert content(igniter, "assets/css/app.css") =~
             ~s(@import "../../deps/hakushi/priv/static/hakushi.css";)

    assert content(igniter, "assets/css/app.css") =~
             ~s(/* @import "../../deps/hakushi/priv/static/hakushi-sumi.css"; */)

    # After the last import of html_helpers.
    assert content(igniter, "lib/test_web.ex") =~
             "import TestWeb.CoreComponents\n      import Hakushi.Components\n      alias"

    assert_unchanged(igniter, "config/config.exs")
    assert_has_notice(igniter, &(&1 =~ "Sumi theme"))
    refute Enum.any?(igniter.notices, &(&1 =~ "NODE_PATH"))
    assert igniter.warnings == []
  end

  test "a second run changes nothing" do
    project()
    |> install()
    |> apply_igniter!()
    |> install()
    |> assert_unchanged()
  end

  test "an import of the components already there is kept, not added again" do
    web =
      String.replace(
        @web,
        "import Phoenix.HTML\n",
        "import Phoenix.HTML\n      import Hakushi.Components\n"
      )

    project(%{"lib/test_web.ex" => web})
    |> install()
    |> assert_unchanged("lib/test_web.ex")
  end

  test "tells what to add when html_helpers is not there" do
    web = """
    defmodule TestWeb do
    end
    """

    project(%{"lib/test_web.ex" => web})
    |> install()
    |> assert_unchanged("lib/test_web.ex")
    |> assert_has_warning(&(&1 =~ "import Hakushi.Components"))
  end

  test "tells what to add when app.js cannot be edited, and changes nothing in it" do
    project(%{"assets/js/app.js" => "console.log(\"custom\")\n"})
    |> install()
    |> assert_unchanged("assets/js/app.js")
    |> assert_has_warning(&(&1 =~ ~s(import { Hakushi } from "hakushi")))
  end

  test "tells what to add when a file is not there" do
    igniter =
      test_project(files: %{"config/config.exs" => @config_exs, "lib/test_web.ex" => @web})
      |> install()

    assert_has_warning(igniter, &(&1 =~ "assets/js/app.js not found."))
    assert_has_warning(igniter, &(&1 =~ "assets/css/app.css not found."))
  end

  test "tells what to add to NODE_PATH when the esbuild config does not have deps/" do
    project(%{"config/config.exs" => "import Config\n"})
    |> install()
    |> assert_unchanged("config/config.exs")
    |> assert_has_notice(&(&1 =~ ~S|Path.expand("../deps", __DIR__)|))
  end
end
