# The Hakushi development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with a small app ("Atelier", a studio's project
# tool) and four canvases built on Hakushi: the database of the app
# (/, tables with a handle on each column, foreign keys between columns of
# one type), an automation (/workflow, steps dragged from a palette, a
# condition with two ways out, no cycles), a moodboard (/board, notes that
# resize, swatches, labelled arrows, snapped to the grid) and two thousand
# nodes in a grid, joined to their neighbours (/scale, `?n=` for another
# count). The schema and the workflow are
# shared: open them in two windows as two people. The graphs are kept in
# memory while the server runs. The browser tests in e2e/ run against it.
#
# The bundle is built first when it is missing, then rebuilds and the page
# reloads on a change.
#
# Query params of every page: `as` - who you are: `ada` (the default),
# `kenji`, `ines`, or `viewer` (read-only); `theme=sumi`, `dark=1`.
#
# Environment:
#
#   * PORT - the HTTP port (4099).
#   * HAKUSHI_DEV_WATCH - "false" starts no esbuild watcher and no live
#     reload, for the browser tests; the bundle must be built first.

port = "PORT" |> System.get_env("4099") |> String.to_integer()
watch? = System.get_env("HAKUSHI_DEV_WATCH") != "false"

Application.put_env(:phoenix, :json_library, JSON)
Application.put_env(:issho, Issho.MCP, instance: HakushiDev.Issho)
Logger.configure(level: :info)

Application.put_env(:hakushi, HakushiDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  code_reloader: watch?,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "hakushi-dev-live-view-salt"],
  pubsub_server: HakushiDev.PubSub,
  render_errors: [formats: [html: HakushiDev.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("hakushi-development-secret-", 3),
  server: true,
  url: [host: "localhost"],
  watchers:
    if(watch?,
      do: [hakushi_esm: {Esbuild, :install_and_run, [:hakushi_esm, ~w(--watch)]}],
      else: []
    ),
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.js$",
      ~r"assets/css/.*\.css$",
      ~r"lib/hakushi/.*\.ex$"
    ]
  ]
)

unless File.exists?(Path.expand("priv/static/hakushi.esm.js", __DIR__)) do
  Mix.Task.run("hakushi.build")
end

defmodule HakushiDev.People do
  @moduledoc "Who you are in the development app (`?as=`)."

  @people %{
    "ada" => %{id: "ada", name: "Ada Okafor", color: "#b5643c"},
    "kenji" => %{id: "kenji", name: "Kenji Mori", color: "#2e6b5c"},
    "ines" => %{id: "ines", name: "Inês Moreira", color: "#6a4fb3"},
    "viewer" => %{id: "viewer", name: "Sam Reader", color: "#79736a"}
  }

  def get(nil), do: @people["ada"]
  def get(id), do: Map.get(@people, id, @people["ada"])
  def all, do: @people
end

defmodule HakushiDev.Seeds do
  @moduledoc "The canvases of Atelier, as they start."

  alias Hakushi.Graph

  @tables [
    {"clients", 0, 40, "#b5643c", 48,
     [
       {"id", "uuid", :pk},
       {"name", "text", nil},
       {"email", "citext", nil},
       {"created_at", "timestamptz", nil}
     ]},
    {"projects", 360, 0, "#2e6b5c", 214,
     [
       {"id", "uuid", :pk},
       {"client_id", "uuid", :fk},
       {"name", "text", nil},
       {"status", "project_status", nil},
       {"due_on", "date", nil}
     ]},
    {"tasks", 720, 80, "#4a6fb3", 3_912,
     [
       {"id", "uuid", :pk},
       {"project_id", "uuid", :fk},
       {"assignee_id", "uuid", :fk},
       {"title", "text", nil},
       {"estimate", "integer", nil},
       {"done_at", "timestamptz", nil}
     ]},
    {"people", 1080, 0, "#a64d79", 7,
     [
       {"id", "uuid", :pk},
       {"name", "text", nil},
       {"role", "text", nil},
       {"avatar_url", "text", nil}
     ]},
    {"time_entries", 1080, 280, "#c08a2b", 28_406,
     [
       {"id", "uuid", :pk},
       {"task_id", "uuid", :fk},
       {"person_id", "uuid", :fk},
       {"minutes", "integer", nil},
       {"logged_on", "date", nil}
     ]},
    {"invoices", 360, 320, "#5b6b7a", 162,
     [
       {"id", "uuid", :pk},
       {"client_id", "uuid", :fk},
       {"project_id", "uuid", :fk},
       {"total", "numeric", nil},
       {"paid_at", "timestamptz", nil}
     ]}
  ]

  @keys [
    {"projects", "client_id", "clients"},
    {"tasks", "project_id", "projects"},
    {"tasks", "assignee_id", "people"},
    {"time_entries", "task_id", "tasks"},
    {"time_entries", "person_id", "people"},
    {"invoices", "client_id", "clients"}
  ]

  def schema do
    Graph.new(
      nodes:
        for {name, x, y, color, rows, columns} <- @tables do
          %{
            id: name,
            type: "table",
            x: x,
            y: y,
            data: %{
              name: name,
              color: color,
              rows: rows,
              columns: for({c, type, key} <- columns, do: %{name: c, type: type, key: key})
            }
          }
        end,
      edges:
        for {from, column, to} <- @keys do
          %{source: from, source_handle: column, target: to, target_handle: "id", path: "smooth"}
        end
    )
  end

  def workflow do
    step = fn id, x, y, kind, title, detail, status ->
      %{id: id, type: kind, x: x, y: y, data: %{title: title, detail: detail, status: status}}
    end

    Graph.new(
      nodes: [
        step.("paid", 0, 120, "trigger", "Invoice paid", "Stripe · invoice.paid", "done"),
        step.("big", 300, 112, "condition", "Over €5,000?", "invoice.total > 5000", "done"),
        step.("lead", 620, 0, "slack", "Tell the account lead", "Slack · #accounts", "done"),
        step.(
          "thanks",
          920,
          0,
          "email",
          "Send a thank-you letter",
          "Email · from the studio",
          "running"
        ),
        step.("receipt", 620, 250, "email", "Send the receipt", "Email · receipt.pdf", "skipped"),
        step.(
          "close",
          1220,
          120,
          "update",
          "Mark the project paid",
          "projects.status = paid",
          "waiting"
        ),
        step.("wait", 1520, 120, "wait", "Wait 30 days", "then ask for a review", "waiting")
      ],
      edges: [
        %{source: "paid", target: "big", path: "smooth"},
        %{source: "big", source_handle: "yes", target: "lead", path: "smooth", label: "Yes"},
        %{source: "big", source_handle: "no", target: "receipt", path: "smooth", label: "No"},
        %{source: "lead", target: "thanks", path: "smooth"},
        %{source: "thanks", target: "close", path: "smooth", animated: true},
        %{source: "receipt", target: "close", path: "smooth"},
        %{source: "close", target: "wait", path: "smooth"}
      ]
    )
  end

  def board do
    note = fn id, x, y, w, h, tone, text ->
      %{id: id, type: "note", x: x, y: y, width: w, height: h, data: %{tone: tone, text: text}}
    end

    Graph.new(
      nodes: [
        %{
          id: "title",
          type: "title",
          x: 0,
          y: -120,
          data: %{text: "Harbour Museum", sub: "Rebrand · moodboard · week 3"}
        },
        note.(
          "tide",
          0,
          0,
          220,
          140,
          "yellow",
          "The tide comes in twice a day: the identity should feel like it moves."
        ),
        note.("rope", 0, 180, 220, 120, "pink", "Rope, brass, salt-white walls. Nothing glossy."),
        note.(
          "voice",
          520,
          380,
          240,
          120,
          "blue",
          "Voice: a curator who loves the sea, not a brochure."
        ),
        %{
          id: "palette",
          type: "swatches",
          x: 280,
          y: 0,
          data: %{
            title: "Palette",
            colors: [
              {"Harbour", "#1f3b4d"},
              {"Brass", "#b8893b"},
              {"Salt", "#efe9de"},
              {"Signal", "#d2553a"}
            ]
          }
        },
        %{
          id: "type",
          type: "specimen",
          x: 280,
          y: 200,
          data: %{family: "Cormorant Garamond", sample: "Aa", note: "Titles · light"}
        },
        %{
          id: "signage",
          type: "frame",
          x: 800,
          y: -20,
          width: 260,
          height: 380,
          data: %{title: "Signage"}
        },
        "wayfinding"
        |> note.(
          820,
          40,
          220,
          130,
          "green",
          "Wayfinding: numbers big enough to read from the quay."
        )
        |> Map.put(:parent, "signage"),
        "question"
        |> note.(820, 220, 220, 110, "yellow", "Can the logo work stamped in brass?")
        |> Map.put(:parent, "signage")
      ],
      edges: [
        %{source: "tide", target: "palette", label: "sets", path: "bezier"},
        %{source: "rope", target: "type", label: "texture", path: "bezier"},
        %{source: "palette", target: "wayfinding", path: "bezier"},
        %{source: "type", target: "voice", label: "tone", path: "bezier", marker: "dot"},
        %{source: "wayfinding", target: "question", path: "straight"}
      ]
    )
  end

  def scale(n) do
    columns = 50

    Graph.new(
      nodes:
        for i <- 0..(n - 1) do
          %{
            id: "n#{i}",
            x: rem(i, columns) * 220,
            y: div(i, columns) * 110,
            data: %{label: "Node #{i + 1}"}
          }
        end,
      # Each node to the next of its row, and every fifth down to the row below.
      edges:
        for(
          i <- 0..(n - 2)//1,
          rem(i, columns) != columns - 1,
          do: %{id: "r#{i}", source: "n#{i}", target: "n#{i + 1}"}
        ) ++
          for(
            i <- 0..(n - 1)//5,
            i + columns < n,
            do: %{
              id: "d#{i}",
              source: "n#{i}",
              source_handle: "down",
              target: "n#{i + columns}",
              target_handle: "up",
              path: "smooth"
            }
          )
    )
  end
end

defmodule HakushiDev.Store do
  @moduledoc "The graphs of the canvases, in an Agent, as their on_change saves them."
  use Agent

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          "schema" => HakushiDev.Seeds.schema(),
          "workflow" => HakushiDev.Seeds.workflow(),
          "board" => HakushiDev.Seeds.board()
        }
      end,
      name: __MODULE__
    )
  end

  @doc "The graph of a canvas: of its room (`?room=`, for the browser tests) or the app's own."
  def get(name, room \\ nil) do
    key = key(name, room)

    Agent.get_and_update(__MODULE__, fn graphs ->
      graph = Map.get_lazy(graphs, key, fn -> seed(name) end)
      {graph, Map.put(graphs, key, graph)}
    end)
  end

  def put(name, room, graph), do: Agent.update(__MODULE__, &Map.put(&1, key(name, room), graph))

  def key(name, nil), do: name
  def key(name, room), do: name <> ":" <> room

  # A fresh copy of the seed for each room of the tests.
  def seed(name), do: apply(HakushiDev.Seeds, String.to_existing_atom(name), [])
end

defmodule HakushiDev.Icons do
  @moduledoc "The icons of the app, strokes of currentColor."
  use Phoenix.Component

  @paths %{
    "schema" =>
      ~s(<ellipse cx="12" cy="5" rx="8" ry="3"/><path d="M4 5v6c0 1.7 3.6 3 8 3s8-1.3 8-3V5"/><path d="M4 11v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>),
    "workflow" =>
      ~s(<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/><path d="M10 6.5h4a3 3 0 0 1 3 3V14"/>),
    "board" =>
      ~s(<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/>),
    "scale" =>
      ~s(<circle cx="6" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="6" cy="18" r="2"/><circle cx="18" cy="18" r="2"/><circle cx="12" cy="12" r="2"/>),
    "trigger" => ~s(<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>),
    "condition" =>
      ~s(<path d="M6 3v6a3 3 0 0 0 3 3h6a3 3 0 0 1 3 3v6"/><path d="M6 21v-6"/><circle cx="6" cy="12" r="1"/>),
    "email" => ~s(<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/>),
    "slack" => ~s(<path d="M8 3v18M16 3v18M3 8h18M3 16h18"/>),
    "update" => ~s(<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 1 1 3 3L7 19l-4 1 1-4z"/>),
    "wait" => ~s(<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>),
    "webhook" =>
      ~s(<path d="M18 16.98h-5.99c-1.1 0-1.95.94-2.48 1.9A4 4 0 0 1 2 17c.01-.7.2-1.4.57-2"/><path d="m6 17 3.13-5.78c.53-.97.1-2.18-.5-3.1a4 4 0 1 1 6.89-4.06"/><path d="m12 6 3.13 5.73C15.66 12.7 16.9 13 18 13a4 4 0 0 1 0 8"/>),
    "key" => ~s(<circle cx="8" cy="15" r="4"/><path d="m10.8 12.2 8.2-8.2M17 6l2 2M15 8l2 2"/>),
    "link" =>
      ~s(<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>),
    "plus" => ~s(<path d="M12 5v14M5 12h14"/>),
    "check" => ~s(<path d="M20 6 9 17l-5-5"/>),
    "note" =>
      ~s(<path d="M15.5 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8.5z"/><path d="M15 3v6h6"/>),
    "frame" => ~s(<path d="M7 3v18M17 3v18M3 7h18M3 17h18"/>)
  }

  attr :name, :string, required: true
  attr :class, :string, default: "icon"

  def icon(assigns) do
    assigns = assign(assigns, :body, Map.fetch!(@paths, assigns.name))

    ~H"""
    <svg class={@class} viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">{Phoenix.HTML.raw(@body)}</svg>
    """
  end
end

defmodule HakushiDev.Layouts do
  @moduledoc """
  The root layout (the style sheets, the import map, the LiveSocket) and
  the app's frame: the side bar, the top bar, and the panel to be someone
  else or change the theme.
  """
  use Phoenix.Component

  import HakushiDev.Icons

  def root(assigns) do
    params = assigns.conn.params

    assigns =
      assigns
      |> assign(:sumi, params["theme"] == "sumi")
      |> assign(:dark, params["dark"] == "1")

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={if(@dark, do: "dark", else: "light")} class={@sumi && "sumi"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Atelier · Hakushi development</title>
        <link
          rel="icon"
          href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%230a0a0b'/%3E%3Crect x='17' y='17' width='8' height='8' rx='1' fill='%23e84a1c'/%3E%3Crect x='7.5' y='7.5' width='7' height='7' rx='1' fill='none' stroke='white' stroke-width='1.6'/%3E%3C/svg%3E"
        />
        <link rel="stylesheet" href="/css/hakushi.css" />
        <link :if={@sumi} rel="stylesheet" href="/css/hakushi-sumi.css" />
        <style>
          :root { color-scheme: light; --atelier-accent: #2e6b5c; --atelier-bg: #faf9f7; --atelier-side: #f3f1ed; --atelier-line: #e7e3dc; --atelier-ink: #1f1d1a; --atelier-muted: #79736a; --atelier-card: #fff; }
          [data-theme="dark"] { color-scheme: dark; --atelier-bg: #17161a; --atelier-side: #1e1d21; --atelier-line: #2c2a30; --atelier-ink: #eceae6; --atelier-muted: #9c968e; --atelier-accent: #6fbfa5; --atelier-card: #222126; }
          .sumi { --atelier-bg: var(--hakushi-surface); --atelier-side: var(--hakushi-background); --atelier-line: var(--hakushi-border); --atelier-ink: var(--hakushi-text); --atelier-muted: var(--hakushi-muted); --atelier-accent: var(--hakushi-accent); --atelier-card: var(--hakushi-surface); }
          .sumi body { font-family: var(--hakushi-font); }
          * { box-sizing: border-box; }
          body { margin: 0; background: var(--atelier-bg); color: var(--atelier-ink); font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; -webkit-font-smoothing: antialiased; }
          .app { display: grid; grid-template-columns: 15rem 1fr; height: 100vh; }
          .side { display: flex; flex-direction: column; gap: 1.25rem; padding: 1rem 0.75rem; background: var(--atelier-side); border-right: 1px solid var(--atelier-line); overflow: auto; }
          .studio { display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0.5rem; font-weight: 600; }
          .studio span { display: grid; place-items: center; width: 1.5rem; height: 1.5rem; border-radius: 6px; background: var(--atelier-ink); color: var(--atelier-bg); font-size: 0.75rem; }
          .side nav { display: flex; flex-direction: column; gap: 1px; }
          .side nav a { display: flex; align-items: center; gap: 0.625rem; padding: 0.4rem 0.5rem; border-radius: 6px; color: var(--atelier-muted); font-size: 0.875rem; text-decoration: none; }
          .side nav a:hover, .side nav a[aria-current] { background: color-mix(in oklab, var(--atelier-ink) 6%, transparent); color: var(--atelier-ink); }
          .side h3 { margin: 0 0 0.25rem; padding: 0 0.5rem; color: var(--atelier-muted); font-size: 0.6875rem; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; }
          .icon { width: 1rem; height: 1rem; flex: none; }
          .dev { margin-top: auto; padding: 0.75rem; border: 1px dashed var(--atelier-line); border-radius: 8px; font-size: 0.75rem; color: var(--atelier-muted); line-height: 1.7; }
          .dev a { color: inherit; margin-right: 0.375rem; }
          .dev a[aria-current] { color: var(--atelier-ink); font-weight: 600; text-decoration: none; }
          .main { display: flex; flex-direction: column; min-width: 0; min-height: 0; }
          .top { display: flex; align-items: center; gap: 0.75rem; height: 3.5rem; padding: 0 1.25rem; border-bottom: 1px solid var(--atelier-line); flex: none; }
          .top h1 { margin: 0; font-size: 0.9375rem; font-weight: 600; }
          .top .crumb { color: var(--atelier-muted); font-size: 0.875rem; }
          .top .spacer { flex: 1; }
          .top .hint { color: var(--atelier-muted); font-size: 0.8125rem; }
          .button { display: inline-flex; align-items: center; gap: 0.375rem; height: 2rem; padding: 0 0.75rem; border: 1px solid var(--atelier-line); border-radius: 7px; background: var(--atelier-card); color: var(--atelier-ink); font: inherit; font-size: 0.8125rem; font-weight: 500; }
          .button.primary { background: var(--atelier-accent); border-color: transparent; color: #fff; }
          .stage { position: relative; flex: 1; min-height: 0; display: flex; }
          .stage > .hakushi { flex: 1; height: 100%; }
          .palette { width: 13.5rem; flex: none; padding: 1rem 0.75rem; border-right: 1px solid var(--atelier-line); background: var(--atelier-bg); display: flex; flex-direction: column; gap: 0.375rem; overflow: auto; }
          .palette p { margin: 0 0 0.5rem; padding: 0 0.25rem; color: var(--atelier-muted); font-size: 0.75rem; }
          .palette .hakushi-item { display: flex; align-items: center; gap: 0.625rem; padding: 0.5rem 0.625rem; border: 1px solid var(--atelier-line); border-radius: 8px; background: var(--atelier-card); font-size: 0.8125rem; }
          .palette .hakushi-item:hover { border-color: color-mix(in oklab, var(--atelier-ink) 25%, transparent); }
          .palette .hakushi-item span { display: grid; place-items: center; width: 1.625rem; height: 1.625rem; border-radius: 6px; background: var(--kind, #888); color: #fff; }
          .palette .hakushi-item small { display: block; color: var(--atelier-muted); font-size: 0.6875rem; }

          /* Schema: a table, a row for each column, a handle at each end of a row. */
          .table { width: 15rem; overflow: visible; border: 1px solid var(--atelier-line); border-radius: 10px; background: var(--atelier-card); box-shadow: 0 1px 2px rgba(20, 18, 14, 0.06), 0 4px 12px -6px rgba(20, 18, 14, 0.12); font-size: 0.8125rem; }
          .table header { display: flex; align-items: center; gap: 0.5rem; padding: 0.55rem 0.75rem; border-bottom: 1px solid var(--atelier-line); border-radius: 10px 10px 0 0; background: color-mix(in oklab, var(--table) 9%, var(--atelier-card)); }
          .table header i { width: 0.5rem; height: 0.5rem; border-radius: 99px; background: var(--table); }
          .table header strong { font-weight: 600; font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.8125rem; }
          .table header small { margin-left: auto; color: var(--atelier-muted); font-size: 0.6875rem; }
          .column { position: relative; display: flex; align-items: center; gap: 0.5rem; padding: 0.3rem 0.75rem; font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.75rem; }
          .column + .column { border-top: 1px solid color-mix(in oklab, var(--atelier-line) 60%, transparent); }
          .column .key { width: 0.875rem; color: var(--atelier-muted); display: grid; place-items: center; }
          .column .key .icon { width: 0.75rem; height: 0.75rem; }
          .column[data-key="pk"] .key { color: #c08a2b; }
          .column[data-key="fk"] .key { color: var(--table); }
          .column em { margin-left: auto; color: var(--atelier-muted); font-style: normal; font-size: 0.6875rem; }
          .column .hakushi-handle { --hakushi-handle-size: 8px; opacity: 0; }
          .table:hover .hakushi-handle, .hakushi[data-ui-connecting] .column .hakushi-handle, .column .hakushi-handle[data-ui-from] { opacity: 1; }
          .table .add { display: flex; align-items: center; gap: 0.375rem; width: 100%; padding: 0.375rem 0.75rem; border: 0; border-top: 1px dashed var(--atelier-line); border-radius: 0 0 10px 10px; background: none; color: var(--atelier-muted); font: inherit; font-size: 0.75rem; cursor: pointer; }
          .table .add:hover { color: var(--atelier-ink); }
          .table .add .icon { width: 0.75rem; height: 0.75rem; }

          /* Workflow: a step, with its kind, its words and its state. */
          .step { width: 16.5rem; border: 1px solid var(--atelier-line); border-radius: 12px; background: var(--atelier-card); box-shadow: 0 1px 2px rgba(20, 18, 14, 0.06), 0 6px 16px -10px rgba(20, 18, 14, 0.2); }
          .step .body { position: relative; display: flex; gap: 0.75rem; padding: 0.75rem 0.875rem; }
          .step .kind { display: grid; place-items: center; width: 2rem; height: 2rem; flex: none; border-radius: 8px; background: var(--kind); color: #fff; }
          .step .kind .icon { width: 1.05rem; height: 1.05rem; }
          .step small { display: block; color: var(--atelier-muted); font-size: 0.6875rem; letter-spacing: 0.04em; text-transform: uppercase; font-weight: 600; }
          .step strong { display: block; font-size: 0.875rem; font-weight: 600; line-height: 1.3; }
          .step code { display: block; margin-top: 0.125rem; color: var(--atelier-muted); font-size: 0.75rem; font-family: ui-monospace, "SF Mono", Menlo, monospace; }
          .step footer { display: flex; align-items: center; gap: 0.375rem; padding: 0.4rem 0.875rem; border-top: 1px solid var(--atelier-line); color: var(--atelier-muted); font-size: 0.75rem; }
          .step footer i { width: 0.5rem; height: 0.5rem; border-radius: 99px; background: currentColor; }
          .step[data-status="done"] footer { color: #2e7d55; }
          .step[data-status="running"] footer { color: #c0702b; }
          .step[data-status="running"] { box-shadow: 0 0 0 3px color-mix(in oklab, #c0702b 25%, transparent), 0 6px 16px -10px rgba(20, 18, 14, 0.2); }
          .step[data-status="skipped"] { opacity: 0.6; }
          .step .ways { border-top: 1px solid var(--atelier-line); }
          .step .way { position: relative; display: flex; justify-content: space-between; padding: 0.35rem 0.875rem; font-size: 0.75rem; color: var(--atelier-muted); }
          .step .way + .way { border-top: 1px dashed var(--atelier-line); }

          /* Moodboard: notes, swatches, a specimen. */
          .note { position: relative; width: 100%; height: 100%; padding: 0.875rem 1rem; border-radius: 4px; background: var(--tone); color: #2b2620; font-family: "Segoe Print", "Bradley Hand", "Marker Felt", cursive; font-size: 0.9375rem; line-height: 1.35; box-shadow: 0 1px 1px rgba(0,0,0,0.06), 0 10px 18px -12px rgba(0,0,0,0.35); }
          .note[data-tone="yellow"] { --tone: #fdf0a6; }
          .note[data-tone="pink"] { --tone: #fbd3d6; }
          .note[data-tone="blue"] { --tone: #cfe3f7; }
          .note[data-tone="green"] { --tone: #d3ecd0; }
          .board-title { padding: 0.25rem 0; white-space: nowrap; }
          .frame { position: relative; width: 100%; height: 100%; border: 1.5px dashed color-mix(in oklab, var(--atelier-ink) 28%, transparent); border-radius: 14px; background: color-mix(in oklab, var(--atelier-ink) 3%, transparent); }
          .frame span { position: absolute; top: -1.75rem; left: 0.25rem; padding: 0.125rem 0.5rem; border-radius: 6px; color: var(--atelier-muted); font-size: 0.8125rem; font-weight: 600; cursor: grab; }
          .frame span:hover { background: color-mix(in oklab, var(--atelier-ink) 6%, transparent); color: var(--atelier-ink); }
          .board-title strong { display: block; font: 300 2.75rem/1.1 "Cormorant Garamond", Georgia, serif; letter-spacing: 0.02em; color: var(--atelier-ink); }
          .board-title span { color: var(--atelier-muted); font-size: 0.875rem; }
          .swatches, .specimen { position: relative; width: 13.5rem; padding: 0.75rem; border: 1px solid var(--atelier-line); border-radius: 10px; background: var(--atelier-card); box-shadow: 0 6px 16px -10px rgba(20, 18, 14, 0.25); }
          .swatches small, .specimen small { display: block; margin-bottom: 0.5rem; color: var(--atelier-muted); font-size: 0.6875rem; letter-spacing: 0.04em; text-transform: uppercase; font-weight: 600; }
          .swatches ul { display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.375rem; margin: 0; padding: 0; list-style: none; }
          .swatches li span { display: block; height: 2.75rem; border-radius: 6px; background: var(--swatch); box-shadow: inset 0 0 0 1px rgba(0,0,0,0.08); }
          .swatches li em { display: block; margin-top: 0.25rem; font-size: 0.625rem; font-style: normal; color: var(--atelier-muted); }
          .specimen b { display: block; font: 300 4.5rem/1 "Cormorant Garamond", Georgia, serif; }
          .specimen span { color: var(--atelier-muted); font-size: 0.75rem; }
          .note .hakushi-handle, .swatches .hakushi-handle, .specimen .hakushi-handle { opacity: 0; }
          .hakushi-node:hover .hakushi-handle, .hakushi[data-ui-connecting] .hakushi-handle { opacity: 1; }

          .people-strip { display: flex; align-items: center; }
          .people-strip span { display: grid; place-items: center; width: 1.75rem; height: 1.75rem; margin-left: -6px; border: 2px solid var(--atelier-bg); border-radius: 99px; color: #fff; font-size: 0.625rem; font-weight: 600; }
          .scale-node { padding: 0.5rem 0.75rem; border: 1px solid var(--atelier-line); border-radius: 8px; background: var(--atelier-card); font-size: 0.8125rem; width: 9rem; position: relative; }
        </style>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@300&display=swap" />
        <script type="importmap">
          {
            "imports": {
              "phoenix": "/vendor/phoenix/phoenix.mjs",
              "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
              "hakushi": "/assets/hakushi.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix"
          import { LiveSocket } from "phoenix_live_view"
          import { Hakushi, canvasOf } from "hakushi"

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: { Hakushi },
            params: { _csrf_token: csrfToken }
          })
          liveSocket.connect()
          window.liveSocket = liveSocket
          window.canvasOf = (id) => canvasOf(document.getElementById(id))
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :page, :atom, required: true
  attr :me, :map, required: true
  attr :query, :map, required: true
  attr :title, :string, required: true
  attr :crumb, :string, default: nil
  slot :actions
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="app">
      <aside class="side">
        <div class="studio"><span>H</span> Hattori Studio</div>
        <nav>
          <h3>Atelier</h3>
          <.link
            :for={{page, path, label, icon} <- pages()}
            navigate={path <> qs(@query, %{})}
            aria-current={@page == page && "page"}
          >
            <.icon name={icon} /> {label}
          </.link>
        </nav>
        <div class="dev">
          You are {@me.name}. Be:
          <a
            :for={{id, name} <- [{"ada", "Ada"}, {"kenji", "Kenji"}, {"ines", "Inês"}, {"viewer", "a viewer"}]}
            href={"?" <> URI.encode_query(Map.put(@query, "as", id))}
            aria-current={@me.id == id && "true"}
          >{name}</a>
          <br /> Theme:
          <a href={"?" <> URI.encode_query(Map.drop(@query, ["theme", "dark"]))} aria-current={!@query["theme"] && !@query["dark"] && "true"}>Hakushi</a>
          <a href={"?" <> URI.encode_query(@query |> Map.put("theme", "sumi") |> Map.delete("dark"))} aria-current={@query["theme"] == "sumi" && !@query["dark"] && "true"}>Sumi</a>
          <a href={"?" <> URI.encode_query(Map.put(@query, "dark", "1"))} aria-current={@query["dark"] == "1" && "true"}>Dark</a>
          <br /> Open this page in another window as Kenji: the canvas is shared.
        </div>
      </aside>
      <section class="main">
        <header class="top">
          <h1>{@title}</h1>
          <span :if={@crumb} class="crumb">{@crumb}</span>
          <span class="spacer"></span>
          {render_slot(@actions)}
        </header>
        <div class="stage">
          {render_slot(@inner_block)}
        </div>
      </section>
    </div>
    """
  end

  defp pages do
    [
      {:schema, "/", "Schema", "schema"},
      {:workflow, "/workflow", "Workflow", "workflow"},
      {:board, "/board", "Moodboard", "board"},
      {:scale, "/scale", "Two thousand nodes", "scale"}
    ]
  end

  def qs(query, extra) do
    case Map.merge(Map.take(query, ["as", "theme", "dark", "room"]), extra) do
      empty when map_size(empty) == 0 -> ""
      query -> "?" <> URI.encode_query(query)
    end
  end
end

defmodule HakushiDev.Collaboration do
  @moduledoc """
  Who may do what on the shared canvases of the development app: anyone,
  anything. An app answers from its own permissions.
  """
  @behaviour Issho.Policy

  @impl true
  def authorize(_who, "atelier:" <> _canvas, _action), do: :ok
  def authorize(_who, _room, _action), do: {:error, :forbidden}
end

defmodule HakushiDev.Page do
  @moduledoc "What every page of the app mounts with: who you are, and the query."
  import Phoenix.Component, only: [assign: 3]

  def topic(name, nil), do: "atelier:" <> name
  def topic(name, room), do: "atelier:" <> name <> ":" <> room

  def on_mount(:default, params, _session, socket) do
    me = HakushiDev.People.get(params["as"])

    {:cont,
     socket
     |> assign(:me, me)
     |> assign(:readonly, params["as"] == "viewer")
     |> assign(:room, params["room"])
     |> assign(:query, Map.take(params, ["as", "theme", "dark", "room"]))}
  end
end

defmodule HakushiDev.SchemaLive do
  @moduledoc "The database of Atelier: tables, and foreign keys between columns of one type."
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Icons
  import HakushiDev.Layouts, only: [app: 1]
  import HakushiDev.Page, only: [topic: 2]

  alias Hakushi.{Change, Graph}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, graph: HakushiDev.Store.get("schema", socket.assigns.room))}
  end

  @impl true
  def handle_event("add_column", %{"table" => table}, socket) do
    case Hakushi.Issho.graph(HakushiDev.Issho, topic("schema", socket.assigns.room))
         |> Kernel.||(socket.assigns.graph)
         |> Graph.node(table) do
      nil ->
        {:noreply, socket}

      node ->
        n = length(node.data.columns)
        column = %{name: "column_#{n}", type: "text", key: nil}
        data = %{node.data | columns: node.data.columns ++ [column]}
        Hakushi.Live.change("schema", Change.update(nodes: [%{id: table, data: data}]))
        {:noreply, socket}
    end
  end

  # A foreign key joins columns of one type; the browser shows only those,
  # and the server checks again.
  def on_change(%Change{op: :connect, edges: [edge]}, %{graph: graph, result: result}, room) do
    source = column(graph, edge.source, edge.source_handle)
    target = column(graph, edge.target, edge.target_handle)

    cond do
      is_nil(source) or is_nil(target) ->
        {:error, "Join a column to a column."}

      source.type != target.type ->
        {:error,
         "#{edge.source}.#{source.name} is #{source.type} and #{edge.target}.#{target.name} is #{target.type}: they do not join."}

      true ->
        HakushiDev.Store.put("schema", room, result)
        :ok
    end
  end

  def on_change(_change, %{result: result}, room) do
    HakushiDev.Store.put("schema", room, result)
    :ok
  end

  defp column(graph, table, name) do
    with %{data: %{columns: columns}} <- Graph.node(graph, table),
         do: Enum.find(columns, &(&1.name == name))
  end

  def new_node("table", {x, y}) do
    %{
      type: "table",
      x: x,
      y: y,
      data: %{
        name: "new_table",
        color: "#79736a",
        rows: 0,
        columns: [%{name: "id", type: "uuid", key: :pk}]
      }
    }
  end

  def new_node(_item, _place), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.app page={:schema} me={@me} query={@query} title="Schema" crumb="atelier_prod · 6 tables">
      <:actions>
        <span class="hint">Drag from a column's dot to a column of another table.</span>
        <.canvas_item :if={!@readonly} for="schema" item="table" class="button primary">
          <.icon name="plus" /> New table
        </.canvas_item>
      </:actions>
      <.canvas
        id="schema"
        graph={@graph}
        on_change={&on_change(&1, &2, @room)}
        new_node={&new_node/2}
        live={{HakushiDev.Issho, topic("schema", @room)}}
        user={@me}
        readonly={@readonly}
        background={:lines}
        grid={20}
        label="The tables of Atelier"
      >
        <:node type="table" :let={node}>
          <div class="table" style={"--table: #{node.data.color}"}>
            <header>
              <i></i>
              <strong>{node.data.name}</strong>
              <small>{rows(node.data.rows)}</small>
            </header>
            <div :for={column <- node.data.columns} class="column" data-key={column.key} data-column={column.name}>
              <.handle id={column.name} side={:left} type={column.type} accepts={[column.type]} label={"#{node.data.name}.#{column.name}"} />
              <span class="key">
                <.icon :if={column.key == :pk} name="key" />
                <.icon :if={column.key == :fk} name="link" />
              </span>
              {column.name}
              <em>{column.type}</em>
              <.handle id={column.name} side={:right} type={column.type} accepts={[column.type]} label={"#{node.data.name}.#{column.name}"} />
            </div>
            <button :if={!@readonly} class="add" type="button" phx-click="add_column" phx-value-table={node.id}>
              <.icon name="plus" /> Column
            </button>
          </div>
        </:node>
      </.canvas>
    </.app>
    """
  end

  defp rows(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k rows"
  defp rows(n), do: "#{n} rows"
end

defmodule HakushiDev.WorkflowLive do
  @moduledoc "An automation of Atelier: steps from a palette, a condition, no cycles."
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Icons
  import HakushiDev.Layouts, only: [app: 1]
  import HakushiDev.Page, only: [topic: 2]

  @kinds %{
    "trigger" => {"Trigger", "#c0702b"},
    "condition" => {"Condition", "#6a4fb3"},
    "email" => {"Email", "#4a6fb3"},
    "slack" => {"Slack", "#a64d79"},
    "update" => {"Update a record", "#2e6b5c"},
    "wait" => {"Wait", "#79736a"},
    "webhook" => {"Webhook", "#5b6b7a"}
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, graph: HakushiDev.Store.get("workflow", socket.assigns.room), kinds: @kinds)}
  end

  def on_change(_change, %{result: result}, room) do
    HakushiDev.Store.put("workflow", room, result)
    :ok
  end

  def new_node(kind, {x, y}) when is_map_key(@kinds, kind) do
    {label, _color} = @kinds[kind]

    %{
      type: kind,
      x: x,
      y: y,
      data: %{title: "New #{String.downcase(label)}", detail: "Not set up yet", status: "draft"}
    }
  end

  def new_node(_kind, _place), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.app page={:workflow} me={@me} query={@query} title="Workflow" crumb="When an invoice is paid">
      <:actions>
        <span class="hint">Live · ran 3 minutes ago</span>
        <span class="button primary"><.icon name="check" /> Published</span>
      </:actions>
      <aside :if={!@readonly} class="palette">
        <p>Drag a step onto the canvas, or press Enter on one.</p>
        <.canvas_item :for={{kind, {label, color}} <- Enum.sort(@kinds)} for="workflow" item={kind} style={"--kind: #{color}"}>
          <span><.icon name={kind} /></span>
          <div>{label}<small>{detail(kind)}</small></div>
        </.canvas_item>
      </aside>
      <.canvas
        id="workflow"
        graph={@graph}
        on_change={&on_change(&1, &2, @room)}
        new_node={&new_node/2}
        live={{HakushiDev.Issho, topic("workflow", @room)}}
        user={@me}
        readonly={@readonly}
        rules={[cycles: false]}
        background={:dots}
        label="The steps of the workflow"
      >
        <:node :let={node}>
          <div class="step" data-status={node.data.status} style={"--kind: #{kind_color(node.type)}"}>
            <div class="body">
              <.handle :if={node.type != "trigger"} kind={:target} side={:left} />
              <span class="kind"><.icon name={node.type} /></span>
              <div>
                <small>{kind_label(node.type)}</small>
                <strong>{node.data.title}</strong>
                <code>{node.data.detail}</code>
              </div>
              <.handle :if={node.type != "condition"} kind={:source} side={:right} />
            </div>
            <div :if={node.type == "condition"} class="ways">
              <div class="way">Yes <.handle id="yes" kind={:source} side={:right} max={1} label="Yes" /></div>
              <div class="way">No <.handle id="no" kind={:source} side={:right} max={1} label="No" /></div>
            </div>
            <footer><i></i> {status(node.data.status)}</footer>
          </div>
        </:node>
      </.canvas>
    </.app>
    """
  end

  defp kind_label(kind), do: @kinds |> Map.get(kind, {"Step", nil}) |> elem(0)
  defp kind_color(kind), do: @kinds |> Map.get(kind, {nil, "#79736a"}) |> elem(1)

  defp detail("trigger"), do: "What starts it"
  defp detail("condition"), do: "Two ways on"
  defp detail("email"), do: "A letter to the client"
  defp detail("slack"), do: "A message to the team"
  defp detail("update"), do: "Change a project"
  defp detail("wait"), do: "Days, or until a date"
  defp detail("webhook"), do: "Call another app"

  defp status("done"), do: "Ran · 14:02"
  defp status("running"), do: "Running"
  defp status("skipped"), do: "Skipped"
  defp status("waiting"), do: "Waiting"
  defp status(_draft), do: "Draft"
end

defmodule HakushiDev.BoardLive do
  @moduledoc "A moodboard: notes that resize, swatches, a specimen, labelled arrows."
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Icons
  import HakushiDev.Layouts, only: [app: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, graph: HakushiDev.Store.get("board", socket.assigns.room))}
  end

  def on_change(_change, %{result: result}, room) do
    HakushiDev.Store.put("board", room, result)
    :ok
  end

  def new_node("frame", {x, y}),
    do: %{type: "frame", x: x, y: y, width: 360, height: 260, data: %{title: "A frame"}}

  def new_node(_item, {x, y}),
    do: %{
      type: "note",
      x: x,
      y: y,
      width: 200,
      height: 120,
      data: %{tone: "yellow", text: "A new note"}
    }

  @impl true
  def render(assigns) do
    ~H"""
    <.app page={:board} me={@me} query={@query} title="Moodboard" crumb="Harbour Museum rebrand">
      <:actions>
        <span class="hint">Double-click the paper for a note. Drop notes in a frame; move a frame by its name.</span>
        <.canvas_item :if={!@readonly} for="board" item="frame" class="button"><.icon name="frame" /> Frame</.canvas_item>
        <.canvas_item :if={!@readonly} for="board" item="note" class="button"><.icon name="note" /> Note</.canvas_item>
      </:actions>
      <.canvas
        id="board"
        graph={@graph}
        on_change={&on_change(&1, &2, @room)}
        new_node={&new_node/2}
        readonly={@readonly}
        background={:cross}
        grid={20}
        snap
        rules={[loops: false]}
        label="The moodboard"
      >
        <:node type="note" resizable :let={node}>
          <div class="note" data-tone={node.data.tone}>
            <.handle kind={:both} side={:right} /><.handle kind={:both} side={:left} />
            {node.data.text}
          </div>
        </:node>
        <:node type="frame" group resizable :let={node}>
          <div class="frame"><span data-hakushi-drag>{node.data.title}</span></div>
        </:node>
        <:node type="title" :let={node}>
          <div class="board-title"><strong>{node.data.text}</strong><span>{node.data.sub}</span></div>
        </:node>
        <:node type="swatches" :let={node}>
          <div class="swatches">
            <.handle kind={:both} side={:left} /><.handle kind={:both} side={:right} />
            <small>{node.data.title}</small>
            <ul>
              <li :for={{name, color} <- node.data.colors}><span style={"--swatch: #{color}"}></span><em>{name}</em></li>
            </ul>
          </div>
        </:node>
        <:node type="specimen" :let={node}>
          <div class="specimen">
            <.handle kind={:both} side={:left} /><.handle kind={:both} side={:right} /><.handle kind={:both} side={:bottom} />
            <small>Type</small>
            <b>{node.data.sample}</b>
            <span>{node.data.family} · {node.data.note}</span>
          </div>
        </:node>
      </.canvas>
    </.app>
    """
  end
end

defmodule HakushiDev.ScaleLive do
  @moduledoc "Two thousand nodes (or `?n=`), and an edge to each from its parent."
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Layouts, only: [app: 1]

  @impl true
  def mount(params, _session, socket) do
    n = params |> Map.get("n", "2000") |> String.to_integer() |> min(20_000) |> max(2)
    graph = HakushiDev.Seeds.scale(n)
    {:ok, assign(socket, n: n, edges: map_size(graph.edges), graph: graph)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app page={:scale} me={@me} query={@query} title="Two thousand nodes" crumb={"#{@n} nodes · #{@edges} edges"}>
      <:actions>
        <span class="hint">Only the nodes near the screen are laid out: zoom out, pan, drag. Try <code>?n=10000</code>.</span>
      </:actions>
      <.canvas id="scale" graph={@graph} readonly={@readonly} fit={false} background={:dots} label="Many nodes">
        <:node :let={node}>
          <div class="scale-node">
            <.handle kind={:target} side={:left} />
            <.handle id="up" kind={:target} side={:top} />
            {node.data.label}
            <.handle kind={:source} side={:right} />
            <.handle id="down" kind={:source} side={:bottom} />
          </div>
        </:node>
      </.canvas>
    </.app>
    """
  end
end

defmodule HakushiDev.MCP do
  @moduledoc """
  MCP for agents: Issho's room tools and Hakushi's canvas tools, at /mcp,
  with no authorization (development only): an agent is named for its
  client and acts as itself. Claude Code connects with
  `claude mcp add --transport http hakushi-dev http://localhost:4099/mcp`,
  and works on the canvases open in a browser (the schema's room is
  `atelier:schema`, or `atelier:schema:ROOM` with `?room=ROOM`).
  """
  use Sake.Server, name: "hakushi-dev", version: "0.0.0"
  mount(Issho.MCP)
  mount(Hakushi.Issho.MCP)
end

defmodule HakushiDev.AgentPlug do
  @moduledoc false
  # For the browser tests: calls a tool of /mcp as an MCP client does, over
  # HTTP, with Sake's client. POST {"tool": ..., "arguments": {...}}.
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    %{"tool" => tool, "arguments" => arguments} = conn.body_params
    url = "http://127.0.0.1:#{conn.port}/mcp"

    {:ok, session} =
      Sake.Client.connect(url, client_info: %{"name" => "claude-code", "title" => "Claude Code"})

    reply =
      case Sake.Client.call_tool(session, tool, arguments) do
        {:ok, %{is_error: true, text: text}, _session} -> %{"error" => text}
        {:ok, result, _session} -> %{"result" => result.structured || result.text}
        {:error, reason, _session} -> %{"error" => inspect(reason)}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, JSON.encode!(reply))
  end
end

defmodule HakushiDev.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Sake.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {HakushiDev.Layouts, :root})
  end

  scope "/" do
    sake_endpoint("/mcp", server: HakushiDev.MCP, secret: String.duplicate("hakushi-dev-mcp-", 4))
    post("/dev/agent", HakushiDev.AgentPlug, [])
  end

  scope "/" do
    pipe_through(:browser)

    live_session :default, on_mount: [HakushiDev.Page, Hakushi.Live] do
      live("/", HakushiDev.SchemaLive)
      live("/workflow", HakushiDev.WorkflowLive)
      live("/board", HakushiDev.BoardLive)
      live("/scale", HakushiDev.ScaleLive)
    end
  end
end

defmodule HakushiDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule HakushiDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :hakushi

  @session [store: :cookie, key: "_hakushi_dev", signing_salt: "hakushi-dev"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])

  if System.get_env("HAKUSHI_DEV_WATCH") != "false" do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  plug(Plug.Static, at: "/assets", from: Path.expand("priv/static", __DIR__))
  plug(Plug.Static, at: "/css", from: Path.expand("assets/css", __DIR__))
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/vendor/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})

  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: JSON)
  plug(Plug.MethodOverride)
  plug(Plug.Session, @session)
  plug(HakushiDev.Router)
end

# The script's process ends after this file, so the server runs in a task
# that stays alive; `mix run --no-halt` keeps the VM up.
Task.async(fn ->
  if watch?, do: {:ok, _apps} = Application.ensure_all_started(:esbuild)

  {:ok, _pid} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: HakushiDev.PubSub},
        HakushiDev.Store,
        # The room of each shared canvas, its people and their cursors.
        {Issho,
         name: HakushiDev.Issho,
         pubsub: HakushiDev.PubSub,
         endpoint: HakushiDev.Endpoint,
         policy: HakushiDev.Collaboration},
        HakushiDev.Endpoint
      ],
      strategy: :one_for_one
    )

  IO.puts("Hakushi development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
