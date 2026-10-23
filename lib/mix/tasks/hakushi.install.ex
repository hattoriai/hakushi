# The task with Igniter when the app has it, else the plain one: the choice
# is made as the file compiles, since `use Igniter.Mix.Task` does not expand
# in an app without Igniter.
if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Hakushi.Install do
    @shortdoc "Adds Hakushi to a Phoenix app"

    @moduledoc """
    Sets up Hakushi in a Phoenix application.

        $ mix igniter.install hakushi

    or, with Hakushi already in the deps, `mix hakushi.install`.
    [Igniter](https://hexdocs.pm/igniter) shows each change as a diff and
    asks before it writes (`--dry-run` only shows them, `--yes` does not
    ask). Running the task again changes nothing.

      * `assets/js/app.js` imports the `Hakushi` hook and adds it to the
        hooks of the `LiveSocket`;
      * `assets/css/app.css` imports the canvas style sheet, and the Sumi
        theme as a comment;
      * the `html_helpers` of your web module import `Hakushi.Components`.

    When a file is not there, or the task cannot edit it safely, it changes
    nothing in that file and tells you the lines to add. It does not edit
    `config/config.exs`: when the esbuild profile does not resolve `hakushi`
    through `NODE_PATH`, it tells you what to add.

    Without Igniter in the app, `mix hakushi.install` makes the edits of
    the two asset files and prints each change as a diff.
    """

    use Igniter.Mix.Task

    alias Hakushi.Install.Edits
    alias Igniter.Code.Common
    alias Igniter.Code.Function
    alias Igniter.Libs.Phoenix, as: Phx
    alias Igniter.Project.Module, as: Mod
    alias Sourceror.Zipper

    @js "assets/js/app.js"
    @css "assets/css/app.css"
    @config "config/config.exs"

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task), do: %Igniter.Mix.Task.Info{group: :hakushi}

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      deps_path = Mix.Project.deps_path()
      package = Hakushi.Install.package_path(Mix.Project.deps_paths(), deps_path)
      css_dir = Edits.relative(package, Path.dirname(@css))

      igniter
      |> edit(@js, &Edits.app_js/1, Edits.app_js_manual())
      |> edit(@css, &Edits.app_css(&1, css_dir), Edits.app_css_manual(css_dir))
      |> import_components()
      |> esbuild_notice(package, deps_path)
      |> Igniter.add_notice(Hakushi.Install.sumi_note())
    end

    defp edit(igniter, path, fun, manual) do
      if Igniter.exists?(igniter, path) do
        Igniter.update_file(igniter, path, &update_source(&1, fun))
      else
        Igniter.add_warning(igniter, "#{path} not found. " <> manual)
      end
    end

    defp update_source(source, fun) do
      case fun.(Rewrite.Source.get(source, :content)) do
        {:changed, new} -> Rewrite.Source.update(source, :content, new)
        :unchanged -> source
        {:manual, text} -> {:warning, text}
      end
    end

    # `import Hakushi.Components` in the `quote` of `html_helpers/0`, after
    # its last import.
    defp import_components(igniter) do
      web = Phx.web_module(igniter)

      manual = """
      Import the components in the html_helpers of #{inspect(web)}:

          import Hakushi.Components
      """

      case Mod.find_and_update_module(igniter, web, &add_import(&1, manual)) do
        {:ok, igniter} -> igniter
        {:error, igniter} -> Igniter.add_warning(igniter, manual)
      end
    end

    defp add_import(zipper, manual) do
      with {:ok, zipper} <- Function.move_to_defp(zipper, :html_helpers, 0),
           {:ok, zipper} <- Function.move_to_function_call(zipper, :quote, 1),
           {:ok, zipper} <- Common.move_to_do_block(zipper) do
        if imports_components?(Zipper.node(zipper)),
          do: {:ok, zipper},
          else: {:ok, Common.add_code(last_import(zipper), "import Hakushi.Components")}
      else
        _error -> {:warning, manual}
      end
    end

    defp imports_components?(ast) do
      ast
      |> Macro.prewalker()
      |> Enum.any?(&match?({:import, _, [{:__aliases__, _, [:Hakushi, :Components]} | _]}, &1))
    end

    # The last import of the block, else its last expression.
    defp last_import(zipper) do
      case Zipper.node(zipper) do
        {:__block__, _, [_ | _]} ->
          children = zipper |> Zipper.down() |> siblings()

          Enum.find(Enum.reverse(children), List.last(children), fn child ->
            match?({:import, _, _}, Zipper.node(child))
          end)

        _expression ->
          zipper
      end
    end

    defp siblings(nil), do: []
    defp siblings(zipper), do: [zipper | siblings(Zipper.right(zipper))]

    defp esbuild_notice(igniter, package, deps_path) do
      {igniter, config} =
        if Igniter.exists?(igniter, @config) do
          igniter = Igniter.include_existing_file(igniter, @config)
          source = Rewrite.source!(igniter.rewrite, @config)
          {igniter, Rewrite.Source.get(source, :content)}
        else
          {igniter, ""}
        end

      case Hakushi.Install.esbuild_note(config, package, deps_path) do
        {:ok, _note} -> igniter
        {:add, note} -> Igniter.add_notice(igniter, note)
      end
    end
  end
else
  defmodule Mix.Tasks.Hakushi.Install do
    @shortdoc "Adds the Hakushi hook and style sheet to a Phoenix app"

    @moduledoc """
    Sets up Hakushi in a Phoenix application.

        $ mix hakushi.install
        $ mix hakushi.install --dry-run

    The task edits two files:

      * `assets/js/app.js` - adds `import { Hakushi } from "hakushi"` and puts
        `Hakushi` in the `hooks` of the `LiveSocket`. When it cannot find the
        `new LiveSocket(...)` call, or its hooks are not an object or a
        variable, it changes nothing and prints the lines to add.
      * `assets/css/app.css` - adds the canvas style sheet, and the Sumi
        theme import as a comment.

    Then it prints the esbuild note: the app's esbuild must resolve
    `hakushi` through `NODE_PATH`. Import `Hakushi.Components` in the
    `html_helpers` of your web module yourself.

    The task is idempotent: it does not add what a file already has, and
    when there is nothing to add it says so. With
    [Igniter](https://hexdocs.pm/igniter) in the app, the task also imports
    the components: `mix igniter.install hakushi`.

    ## Options

      * `--dry-run` - prints the changes as a diff and writes nothing.
    """

    use Mix.Task

    @impl Mix.Task
    def run(argv), do: Hakushi.Install.run(argv)
  end
end
