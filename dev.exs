# The Hakushi development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with a small app ("Atelier", a studio's project
# tool) and four canvases built on Hakushi: the database of the app
# (/, tables with a handle on each column, foreign keys between columns of
# one type), an automation (/workflow, steps dragged from a palette, a
# condition with two ways out, no cycles), a moodboard (/board, notes that
# resize, swatches, labelled arrows, snapped to the grid, and ink: a pen,
# a highlighter, an eraser and a lasso; images dropped, pasted or picked;
# a picker of papers, one of them the
# app's own) and two thousand
# nodes in a grid, joined to their neighbours (/scale, `?n=` for another
# count). The schema, the workflow and the moodboard are
# shared: open them in two windows as two people. The graphs are kept in
# memory while the server runs. The browser tests in e2e/ run against it.
#
# The bundle is built first when it is missing, then rebuilds and the page
# reloads on a change.
#
# Query params of every page: `as` - who you are: `ada` (the default),
# `kenji`, `ines`, or `viewer` (read-only); `theme=sumi`, `dark=1`, or
# `sumi=smoke` (any of Sumi's seven themes, to see each; /colours has every
# colour of the kits on one canvas). The
# schema with `comments=1` has Issho's comments beside it: threads on its
# tables, said by name.
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

# The moodboard's images (Hakushi.Kits.Images): kept in tmp/uploads, and
# served by Storehouse.Local.Plug. Addresses pasted are fetched from
# two hosts of photos, and from this server itself (over http) for the
# browser tests, which a real app would not allow; an agent's `file` is a
# photo of test/fixtures/images.
Application.put_env(:storehouse, Storehouse.Local, root: Path.expand("tmp/uploads", __DIR__))

Application.put_env(:hakushi, Hakushi.Kits.Images,
  fetch: ["images.unsplash.com", "upload.wikimedia.org", "127.0.0.1", "localhost"],
  http: true,
  files: &HakushiDev.Seeds.photo_path/1
)

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
  alias Hakushi.Kits.{Images, Ink}

  @photos Path.expand("test/fixtures/images", __DIR__)

  @doc "A photo of the moodboard's, by its name (an agent's `file`)."
  def photo_path(name) do
    path = Path.join(@photos, Path.basename(name))
    if File.regular?(path), do: {:ok, path}, else: :error
  end

  # A photo, stored as an upload is (once, for every room of the tests).
  defp photo(name, opts \\ []) do
    key = {__MODULE__, :photo, name}

    with nil <- :persistent_term.get(key, nil) do
      {:ok, image} = Hakushi.Images.store(Path.join(@photos, name), opts)
      :persistent_term.put(key, image)
      image
    end
  end

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
        %{source: "paid", target: "big", path: "routed"},
        %{source: "big", source_handle: "yes", target: "lead", path: "routed", label: "Yes"},
        %{source: "big", source_handle: "no", target: "receipt", path: "routed", label: "No"},
        %{source: "lead", target: "thanks", path: "routed"},
        %{source: "thanks", target: "close", path: "routed", animated: true},
        %{source: "receipt", target: "close", path: "routed"},
        %{source: "close", target: "wait", path: "routed"}
      ]
    )
  end

  # A whiteboard of plain shapes (Hakushi.Kits.Shapes): a little flow of
  # how a feature ships, with a note in text and a line of its own.
  def whiteboard do
    alias Hakushi.Kits.Shapes

    shape = fn id, kind, box, style -> Map.put(Shapes.shape(kind, box, style), :id, id) end
    {:ok, aside} = Shapes.line({700, 330}, {600, 260}, %{"stroke" => "gray", "dash" => true})

    Graph.new(
      nodes: [
        shape.("title", "text", [0, -110, 420, 48], %{
          "text" => "How a feature ships",
          "size" => "l"
        }),
        shape.("idea", "ellipse", [0, 0, 150, 96], %{
          "text" => "Idea",
          "fill" => "yellow",
          "stroke" => "yellow"
        }),
        shape.("sketch", "rect", [230, 0, 170, 96], %{"text" => "Sketch it on the board"}),
        shape.("good", "diamond", [480, 0, 160, 120], %{
          "text" => "Good enough?",
          "fill" => "violet",
          "stroke" => "violet"
        }),
        shape.("ship", "rect", [720, 12, 150, 72], %{
          "text" => "Ship",
          "fill" => "green",
          "stroke" => "green",
          "radius" => 0
        }),
        shape.("again", "triangle", [495, 200, 130, 104], %{
          "text" => "Again",
          "fill" => "red",
          "stroke" => "red",
          "dash" => true
        }),
        shape.("aside", "text", [700, 330, 200, 48], %{
          "text" => "Ask the team first",
          "size" => "s",
          "align" => "left"
        }),
        Map.put(aside, :id, "aside-line")
      ],
      edges: [
        %{source: "idea", target: "sketch", path: "smooth"},
        %{source: "sketch", target: "good", path: "smooth"},
        %{source: "good", target: "ship", path: "smooth", label: "Yes"},
        %{source: "good", target: "again", path: "smooth", label: "No"}
      ]
    )
  end

  def board do
    note = fn id, x, y, w, h, tone, text ->
      %{id: id, type: "note", x: x, y: y, width: w, height: h, data: %{tone: tone, text: text}}
    end

    ink = fn id, points, opts ->
      {:ok, stroke} = Ink.stroke(points, opts)
      Map.put(stroke, :id, id)
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
        |> Map.put(:parent, "signage"),
        # Images: a photo of the quay (with a smaller copy, for small
        # zooms), a texture, and a facade cropped to its top.
        "harbour.jpg"
        |> photo(thumbnail: fn _image, _path -> photo("harbour-small.jpg").url end)
        |> Images.image_node([1120, -20, 360, 0],
          alt: "The quay at dusk: piers against an orange sky",
          caption: "The quay at dusk"
        )
        |> Map.put(:id, "quay"),
        "rope.png"
        |> photo()
        |> Images.image_node([1120, 280, 170, 0], alt: "Waves of brass and green, like rope")
        |> Map.put(:id, "texture"),
        "facade.jpg"
        |> photo()
        |> Images.image_node([1310, 280, 170, 0], alt: "A facade of coloured windows")
        |> Map.put(:id, "facade")
        |> then(fn node ->
          %{node | height: 142, data: Map.put(node.data, "crop", [0.05, 0.05, 0.9, 0.6])}
        end),
        # Ink: a line drawn by hand under the title.
        ink.(
          "underline",
          for(
            i <- 0..40,
            do: [
              4 + i * 7.5,
              -30 + :math.sin(i / 6) * 2.5 + i * 0.08,
              0.35 + 0.4 * :math.sin(i / 40 * :math.pi())
            ]
          ),
          color: "blue",
          size: 3
        )
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

  @doc """
  A database read from a server, as Lotus shows one: `n` tables of a
  schema with no places of their own (the canvas tidies them as it opens),
  a few that many refer to, the types as Postgres names them, and foreign
  keys into a second schema, `billing`, whose tables are stubs.
  """
  def database(n) do
    :rand.seed(:exsss, {7, 11, 13})
    hubs = ["users", "accounts", "projects", "teams"] |> Enum.take(max(1, div(n, 30)))
    names = hubs ++ for(i <- length(hubs)..(n - 1)//1, do: "table_#{i}")

    types = [
      "character varying(255)",
      "text",
      "int4",
      "bigint",
      "numeric(12,2)",
      "boolean",
      "timestamptz",
      "jsonb"
    ]

    {tables, keys} =
      names
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {name, i}, keys ->
        {node, edges} = database_table(name, i, refs(names, hubs, i), types)
        {node, edges ++ keys}
      end)

    invoices = %{
      id: "billing.invoices",
      type: "schema-table",
      x: 0,
      y: 0,
      data: %{
        "name" => "invoices",
        "schema" => "billing",
        "external" => true,
        "columns" => [%{"name" => "id", "type" => "uuid", "key" => "pk"}]
      }
    }

    tables =
      if Enum.any?(keys, &match?({_, _, "billing.invoices", _}, &1)),
        do: tables ++ [invoices],
        else: tables

    Graph.new(
      nodes: tables,
      edges:
        for {from, column, to, to_column} <- Enum.reverse(keys) do
          %{
            source: from,
            source_handle: column,
            target: to,
            target_handle: to_column,
            path: "smooth"
          }
        end
    )
  end

  # A table: its id, the foreign keys of its refs, one to billing.invoices
  # now and then, and fields of the types.
  defp database_table(name, i, refs, types) do
    fks =
      for to <- refs, do: %{"name" => singular(to) <> "_id", "type" => "bigint", "key" => "fk"}

    stub =
      if rem(i, 9) == 4,
        do: [%{"name" => "invoice_id", "type" => "uuid", "key" => "fk"}],
        else: []

    plain =
      for k <- 1..Enum.random(2..9) do
        %{"name" => "field_#{k}", "type" => Enum.random(types), "key" => nil}
      end

    columns = [%{"name" => "id", "type" => "bigint", "key" => "pk"}] ++ fks ++ stub ++ plain

    node = %{
      id: name,
      type: "schema-table",
      x: 0,
      y: 0,
      data: %{"name" => name, "columns" => columns}
    }

    edges =
      for(to <- refs, do: {name, singular(to) <> "_id", to, "id"}) ++
        for(_ <- stub, do: {name, "invoice_id", "billing.invoices", "id"})

    {node, edges}
  end

  # The tables a table refers to: none for a hub, nor for one in eight.
  defp refs(names, hubs, i) do
    cond do
      i < length(hubs) -> []
      :rand.uniform() < 0.12 -> []
      true -> Enum.uniq(for _ <- 1..Enum.random([1, 1, 2, 3]), do: pick_ref(names, hubs, i))
    end
  end

  defp pick_ref(names, hubs, i) do
    if :rand.uniform() < 0.45,
      do: Enum.random(hubs),
      else: Enum.at(names, max(0, i - Enum.random(1..12)))
  end

  defp singular(name), do: String.trim_trailing(name, "s")

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

  # The canvases of the design spec, drawn with the built-in kits.

  defp col(id, name, type, key \\ nil),
    do: %{"id" => id, "name" => name, "type" => type, "key" => key}

  def spec_schema do
    Graph.new(
      nodes: [
        %{
          id: "customers",
          type: "schema-table",
          x: 0,
          y: 30,
          data: %{
            "name" => "customers",
            "columns" => [
              col("c1", "id", "uuid", "pk"),
              col("c2", "email", "text"),
              col("c3", "name", "text")
            ]
          }
        },
        %{
          id: "invoices",
          type: "schema-table",
          x: 320,
          y: 0,
          data: %{
            "name" => "invoices",
            "columns" => [
              col("i1", "id", "uuid", "pk"),
              col("i2", "customer_id", "uuid", "fk"),
              col("i3", "total", "money"),
              col("i4", "paid_at", "timestamp")
            ]
          }
        },
        %{
          id: "lines",
          type: "schema-table",
          x: 640,
          y: 50,
          data: %{
            "name" => "invoice_lines",
            "columns" => [
              col("l1", "id", "uuid", "pk"),
              col("l2", "invoice_id", "uuid", "fk"),
              col("l3", "sku", "text"),
              col("l4", "amount", "money")
            ]
          }
        }
      ],
      edges: [
        %{
          source: "invoices",
          source_handle: "i2",
          target: "customers",
          target_handle: "c1",
          path: :smooth
        },
        %{
          source: "lines",
          source_handle: "l2",
          target: "invoices",
          target_handle: "i1",
          path: :smooth
        }
      ]
    )
  end

  def spec_flow do
    Graph.new(
      nodes: [
        %{
          id: "paid",
          type: "flow-trigger",
          x: 0,
          y: 70,
          data: %{"title" => "Invoice paid", "detail" => "Stripe webhook"}
        },
        %{
          id: "large",
          type: "flow-condition",
          x: 300,
          y: 70,
          data: %{"title" => "Over €1,000?", "detail" => ""}
        },
        %{
          id: "review",
          type: "flow-step",
          x: 620,
          y: 0,
          data: %{"title" => "Ask finance to review", "detail" => "Slack #finance"}
        },
        %{
          id: "receipt",
          type: "flow-step",
          x: 620,
          y: 150,
          data: %{"title" => "Send the receipt", "detail" => "Email"}
        }
      ],
      edges: [
        %{source: "paid", target: "large"},
        %{source: "large", source_handle: "yes", target: "review", animated: true},
        %{source: "large", source_handle: "no", target: "receipt"}
      ]
    )
  end

  def spec_notes do
    Graph.new(
      nodes: [
        %{
          id: "q1",
          type: "note",
          x: 0,
          y: 0,
          width: 200,
          height: 140,
          data: %{
            "text" => "Refunds: a negative invoice, or a table of their own?",
            "color" => "yellow"
          }
        },
        %{
          id: "q2",
          type: "note",
          x: 240,
          y: 20,
          width: 200,
          height: 140,
          data: %{"text" => "Taxes per line, not per invoice.", "color" => "mint"}
        },
        %{
          id: "q3",
          type: "note",
          x: 480,
          y: 0,
          width: 200,
          height: 140,
          data: %{"text" => "Ask legal how long we keep invoices.", "color" => "rose"}
        }
      ],
      edges: [%{source: "q1", target: "q2", path: :straight}]
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
          "board" => HakushiDev.Seeds.board(),
          "whiteboard" => HakushiDev.Seeds.whiteboard()
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

  @doc "The history of a canvas (Hakushi.History), since its first change here."
  def history(name, room) do
    Agent.get(__MODULE__, &Map.get(&1, key(name, room) <> "#history")) ||
      Hakushi.History.new(get(name, room))
  end

  @doc "A change of a canvas, into its history, from the graph it changed."
  def record(name, room, change, %{graph: before, by: by}) do
    Agent.update(__MODULE__, fn state ->
      key = key(name, room) <> "#history"
      history = Map.get_lazy(state, key, fn -> Hakushi.History.new(before) end)

      case Hakushi.History.record(history, change, by: by && by.name) do
        {:ok, history} -> Map.put(state, key, history)
        {:error, _reason, _id} -> Map.put(state, key, Hakushi.History.new(before))
      end
    end)
  end

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
    "whiteboard" =>
      ~s(<rect x="3" y="3" width="8" height="7" rx="1.5"/><circle cx="17" cy="7" r="3.5"/><path d="M3 20h8M13 14l4 6 4-6z"/>),
    "spec" =>
      ~s(<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M16 13H8"/><path d="M16 17H8"/><path d="M10 9H8"/>),
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
  else or change the theme. `?sumi=smoke` (any of Sumi's seven themes)
  loads hakushi-sumi.css on that theme of Sumi.
  """
  use Phoenix.Component

  import HakushiDev.Icons

  # Sumi's themes, as the canvases read them: the paper, the surfaces, the
  # line, the text, the muted text, the accent and the text on it (Sumi's
  # own CSS needs Tailwind, which this app has not; these are its values).
  @sumi_themes [
    {"dark", "Ink", :dark,
     ["oklch(12% 0.003 270)", "oklch(16% 0.004 270)", "oklch(20% 0.005 270)"],
     "oklch(95% 0.012 85)", 0.5, "#e84a1c", "oklch(12% 0.003 270)"},
    {"smoke", "Smoke", :dark,
     ["oklch(27% 0.005 270)", "oklch(30.5% 0.006 270)", "oklch(34% 0.007 270)"],
     "oklch(92% 0.01 85)", 0.62, "oklch(72% 0.13 168)", "oklch(27% 0.005 270)"},
    {"stone", "Stone", :dark,
     ["oklch(20% 0.006 70)", "oklch(23.5% 0.007 70)", "oklch(27% 0.008 70)"],
     "oklch(95% 0.01 85)", 0.52, "oklch(78% 0.13 82)", "oklch(20% 0.006 70)"},
    {"lacquer", "Lacquer", :dark,
     ["oklch(14% 0.022 25)", "oklch(18% 0.026 25)", "oklch(22% 0.03 25)"], "oklch(93% 0.016 75)",
     0.53, "oklch(63% 0.21 24)", "oklch(14% 0.022 25)"},
    {"light", "Paper", :light,
     ["oklch(96% 0.01 85)", "oklch(93% 0.012 85)", "oklch(89% 0.014 80)"], "oklch(15% 0.003 270)",
     0.65, "#e84a1c", "oklch(12% 0.003 270)"},
    {"snow", "Snow", :light,
     ["oklch(99.5% 0.001 270)", "oklch(97% 0.003 270)", "oklch(92.5% 0.005 270)"],
     "oklch(20% 0.006 270)", 0.65, "oklch(50% 0.17 262)", "oklch(100% 0 0)"},
    {"silk", "Silk", :light,
     ["oklch(97.5% 0.012 350)", "oklch(95% 0.016 350)", "oklch(91.5% 0.02 350)"],
     "oklch(22% 0.012 350)", 0.65, "oklch(56% 0.21 358)", "oklch(100% 0 0)"}
  ]

  @doc "Sumi's seven themes: their ids and names."
  def sumi_themes, do: for({id, name, _, _, _, _, _, _} <- @sumi_themes, do: {id, name})

  defp sumi_style(id) do
    case List.keyfind(@sumi_themes, id, 0) do
      {_, _, scheme, [base_100, base_200, base_300], text, muted, accent, on_accent} ->
        """
        :root {
          color-scheme: #{scheme};
          --color-base-100: #{base_100}; --color-base-200: #{base_200}; --color-base-300: #{base_300};
          --color-base-content: #{text}; --sumi-text-muted: oklch(from #{text} l c h / #{muted});
          --color-sumi-blade: #{accent}; --color-primary-content: #{on_accent};
        }
        """

      nil ->
        ""
    end
  end

  def root(assigns) do
    params = assigns.conn.params
    look = if List.keymember?(@sumi_themes, params["sumi"], 0), do: params["sumi"]
    dark = params["dark"] == "1"

    assigns =
      assigns
      |> assign(:sumi, params["theme"] == "sumi" or look != nil)
      |> assign(:look, look)
      |> assign(:dark, dark)
      |> assign(:data_theme, look || if(dark, do: "dark", else: "light"))

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@data_theme} class={@sumi && "sumi"}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Atelier · Hakushi development</title>
        <link
          rel="icon"
          href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='7' fill='%230a0a0b'/%3E%3Crect x='17' y='17' width='8' height='8' rx='1' fill='%23e84a1c'/%3E%3Crect x='7.5' y='7.5' width='7' height='7' rx='1' fill='none' stroke='white' stroke-width='1.6'/%3E%3C/svg%3E"
        />
        <link rel="stylesheet" href="/vendor/issho/issho.css" />
        <link :if={@sumi} rel="stylesheet" href="/vendor/issho/issho-sumi.css" />
        <link rel="stylesheet" href="/css/hakushi.css" />
        <link :if={@sumi} rel="stylesheet" href="/css/hakushi-sumi.css" />
        {@look && Phoenix.HTML.raw("<style>" <> sumi_style(@look) <> "</style>")}
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
          .versions .version { display: grid; gap: 2px; width: 100%; text-align: left; font: inherit; padding: 0.5rem 0.6rem; border: 1px solid var(--atelier-line); border-radius: 8px; background: var(--atelier-card); color: inherit; cursor: pointer; }
          .versions .version small { color: var(--atelier-muted); font-size: 0.75rem; }
          .versions .version.chosen { border-color: var(--atelier-accent); }
          .top .find input { font: inherit; font-size: 0.8125rem; padding: 0.3rem 0.5rem; border: 1px solid var(--atelier-line, #ddd); border-radius: 6px; background: transparent; color: inherit; width: 9rem; }
          .button { display: inline-flex; align-items: center; gap: 0.375rem; height: 2rem; padding: 0 0.75rem; border: 1px solid var(--atelier-line); border-radius: 7px; background: var(--atelier-card); color: var(--atelier-ink); font: inherit; font-size: 0.8125rem; font-weight: 500; }
          .button.primary { background: var(--atelier-accent); border-color: transparent; color: #fff; }
          .stage { position: relative; flex: 1; min-height: 0; display: flex; }
          .stage > .hakushi { flex: 1; height: 100%; }
          .spec { flex: 1; overflow: auto; padding: 8px 32px 120px; }
          .spec > * { max-width: 880px; margin-left: auto; margin-right: auto; }
          .spec h2 { margin: 32px auto 8px; font-size: 18px; }
          .spec p { line-height: 1.6; color: var(--hakushi-text); }
          .spec .end { color: var(--hakushi-muted); }
          .spec-embed { height: 380px; margin-top: 16px; margin-bottom: 16px; }
          .spec-embed.full { position: fixed; inset: 24px; z-index: 50; height: auto; max-width: none; margin: 0; }
          .spec-embed.full .hakushi-embed { position: relative; z-index: 1; border-radius: 14px; box-shadow: 0 24px 80px rgba(0,0,0,.25); }
          .spec-scrim { position: fixed; inset: 0; background: rgba(20,20,30,.35); backdrop-filter: blur(3px); }
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

          /* A paper of the app's own, for the moodboard's picker: isometric,
             a triangle of lines at each square (see Hakushi.Paper). */
          .hakushi[data-background="iso"] .hakushi-background,
          .hakushi-paper-swatch[data-background="iso"] {
            background: var(--hakushi-pattern-strong);
            -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 34.64 20'%3E%3Cpath d='M0 0L34.64 20M34.64 0L0 20M0 0V20M17.32 0V20' fill='none' stroke='black' stroke-width='0.7'/%3E%3C/svg%3E");
            mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 34.64 20'%3E%3Cpath d='M0 0L34.64 20M34.64 0L0 20M0 0V20M17.32 0V20' fill='none' stroke='black' stroke-width='0.7'/%3E%3C/svg%3E");
            -webkit-mask-size: calc(var(--hakushi-grid-size) * 1.732) var(--hakushi-grid-size);
            mask-size: calc(var(--hakushi-grid-size) * 1.732) var(--hakushi-grid-size);
          }

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

          /* Schema with comments=1: Issho's comments beside the canvas. */
          .comments-panel { width: 21rem; flex: none; overflow: auto; padding: 0.75rem; border-left: 1px solid var(--atelier-line); background: var(--atelier-bg); }

          .people-strip { display: flex; align-items: center; }
          .people-strip span { display: grid; place-items: center; width: 1.75rem; height: 1.75rem; margin-left: -6px; border: 2px solid var(--atelier-bg); border-radius: 99px; color: #fff; font-size: 0.625rem; font-weight: 600; }
          .way-label { display: inline-flex; align-items: center; gap: 4px; padding: 1px 4px 1px 8px; border-radius: 99px; background: var(--atelier-card); border: 1px solid var(--atelier-line); font-size: 0.75rem; font-weight: 600; color: var(--atelier-muted); }
          .way-label[data-way="yes"] { color: #2e6b5c; border-color: #2e6b5c55; }
          .way-label[data-way="no"] { color: #b5643c; border-color: #b5643c55; }
          .way-label button { border: 0; background: none; color: inherit; cursor: pointer; font: inherit; padding: 0 2px; }
          .ruler-line { stroke: var(--atelier-accent); stroke-width: 2; vector-effect: non-scaling-stroke; }
          .ruler-text { fill: var(--atelier-accent); font: 600 13px system-ui; text-anchor: middle; }
          .scale-node { padding: 0.5rem 0.75rem; border: 1px solid var(--atelier-line); border-radius: 8px; background: var(--atelier-card); font-size: 0.8125rem; width: 9rem; position: relative; }
        </style>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:wght@300&display=swap" />
        <script type="importmap">
          {
            "imports": {
              "phoenix": "/vendor/phoenix/phoenix.mjs",
              "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
              "issho": "/vendor/issho/issho.esm.js",
              "hakushi": "/assets/hakushi.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix"
          import { LiveSocket } from "phoenix_live_view"
          import { Hooks as Issho } from "issho"
          import { Hakushi, canvasOf, registerTool } from "hakushi"

          // Tools of the app's own (registerTool), on the canvases whose
          // client_tools name them: a ruler, which changes nothing, and a
          // stamp, which drops a note where it is pressed.
          registerTool({
            name: "ruler",
            label: "Ruler",
            key: "m",
            cursor: "crosshair",
            readonly: true,
            icon: '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 17 17 3l4 4L7 21z"/><path d="m7 13 2 2m1-5 2 2m1-5 2 2"/></svg>',
            down(ctx, _event, at) {
              ctx.layer.replaceChildren()
              this.from = at
              this.line = ctx.svg("line", { x1: at.x, y1: at.y, x2: at.x, y2: at.y, class: "ruler-line" })
              this.text = ctx.svg("text", { x: at.x, y: at.y - 8, class: "ruler-text" })
              ctx.layer.append(this.line, this.text)
            },
            move(_ctx, _event, at) {
              this.line.setAttribute("x2", at.x)
              this.line.setAttribute("y2", at.y)
              this.text.setAttribute("x", (this.from.x + at.x) / 2)
              this.text.setAttribute("y", (this.from.y + at.y) / 2 - 8)
              this.text.textContent = `${Math.round(Math.hypot(at.x - this.from.x, at.y - this.from.y))} px`
            },
            up(ctx) {
              ctx.layer.dataset.measured = this.text.textContent
              ctx.announce(this.text.textContent)
            },
            cancel(ctx) {
              ctx.layer.replaceChildren()
            }
          })
          registerTool({
            name: "stamp",
            label: "Stamp a note",
            key: "s",
            up(ctx, _event, at) {
              ctx.drop("note", at)
            }
          })

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: { ...Issho, Hakushi },
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
          <a href={"?" <> URI.encode_query(Map.drop(@query, ["theme", "dark", "sumi"]))} aria-current={!@query["theme"] && !@query["dark"] && !@query["sumi"] && "true"}>Hakushi</a>
          <a href={"?" <> URI.encode_query(@query |> Map.put("theme", "sumi") |> Map.drop(["dark", "sumi"]))} aria-current={@query["theme"] == "sumi" && !@query["dark"] && "true"}>Sumi</a>
          <a href={"?" <> URI.encode_query(@query |> Map.put("dark", "1") |> Map.delete("sumi"))} aria-current={@query["dark"] == "1" && !@query["sumi"] && "true"}>Dark</a>
          <br /> Sumi:
          <a
            :for={{id, name} <- sumi_themes()}
            href={"?" <> URI.encode_query(@query |> Map.put("sumi", id) |> Map.drop(["theme", "dark"]))}
            aria-current={@query["sumi"] == id && "true"}
          >{name}</a>
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
      {:whiteboard, "/whiteboard", "Whiteboard", "whiteboard"},
      {:spec, "/spec", "Design spec", "spec"},
      {:scale, "/scale", "Two thousand nodes", "scale"},
      {:database, "/database", "A database", "schema"},
      {:colours, "/colours", "Every colour", "board"}
    ]
  end

  def qs(query, extra) do
    case Map.merge(Map.take(query, ["as", "theme", "dark", "sumi", "room"]), extra) do
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
     |> assign(:follow, params["follow"] != "false")
     |> assign(:room, params["room"])
     |> assign(:comments, params["comments"] == "1")
     |> assign(:query, Map.take(params, ["as", "theme", "dark", "sumi", "room"]))}
  end
end

defmodule HakushiDev.SchemaLive do
  @moduledoc """
  The database of Atelier: tables, and foreign keys between columns of one
  type. With `?comments=1`, Issho's comments beside it: a thread on what
  you selected, its place said by name ("The node “clients”"), with the
  graph as it is now, which the canvas's events keep.
  """
  use Phoenix.LiveView

  import Hakushi.Components
  import Issho.Components, only: [comments: 1]
  import HakushiDev.Icons
  import HakushiDev.Layouts, only: [app: 1]
  import HakushiDev.Page, only: [topic: 2]

  alias Hakushi.{Change, Graph}

  @impl true
  def mount(params, _session, socket) do
    graph = HakushiDev.Store.get("schema", socket.assigns.room)
    doc = topic("schema", socket.assigns.room)

    # The comments are the room's, in a LiveView that is in it: it joins
    # (the canvas then has the same session), and hears the canvas's
    # changes, as the room's events: the graph of the comments' places, as
    # it is now.
    if connected?(socket) and socket.assigns.comments do
      can = if socket.assigns.readonly, do: :read, else: :write
      {:ok, _session} = Issho.Live.join(HakushiDev.Issho, socket.assigns.me, doc, can: can)
      Issho.Live.subscribe(doc, :self, events: ["canvas.*"])
    end

    # ?grid=app: the app keeps the tables on the paper's squares, giving
    # back another move for one off them (on_change).
    {:ok,
     assign(socket,
       graph: graph,
       now: graph,
       doc: doc,
       selected: [],
       zoom: nil,
       app_grid: params["grid"] == "app"
     )}
  end

  @impl true
  # What the person selects and sees (on_select, on_viewport): the canvas
  # calls them in this process, which sends itself the news.
  def handle_info({:selected, %{nodes: nodes}}, socket),
    do: {:noreply, assign(socket, :selected, nodes)}

  def handle_info({:viewport, %{zoom: zoom}}, socket),
    do: {:noreply, assign(socket, :zoom, zoom)}

  # An item of the canvas's menu (Hakushi.Menu): a column for the table.
  def handle_info({:menu, "add_column", %{nodes: [table]}}, socket),
    do: handle_event("add_column", %{"table" => table}, socket)

  def handle_info({:menu, _item, _target}, socket), do: {:noreply, socket}

  def handle_info({Issho.Live, "event", _room, %Issho.Event{}}, socket) do
    {:noreply, assign(socket, :now, Hakushi.Issho.graph(HakushiDev.Issho, socket.assigns.doc))}
  end

  # The room's other news (its people, their cursors): the canvas's own.
  def handle_info({Issho.Live, _event, _room, _payload}, socket), do: {:noreply, socket}

  @impl true
  # A table found by name: the view goes to it, and selects it.
  def handle_event("find", %{"name" => name}, socket) do
    graph = Hakushi.Issho.graph(HakushiDev.Issho, socket.assigns.doc) || socket.assigns.graph
    name = String.downcase(String.trim(name))

    with %{id: id} <-
           Enum.find(Graph.nodes(graph), &String.contains?(String.downcase(&1.data.name), name)),
         do: Hakushi.Live.focus("schema", id)

    {:noreply, socket}
  end

  def handle_event("show_all", _params, socket) do
    Hakushi.Live.fit("schema")
    {:noreply, socket}
  end

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

  # The tables on the squares of 20: a move off them is given back on them,
  # and saved when it comes back as it is.
  def on_grid(%Change{op: :move, nodes: places} = change, context, room) do
    on_grid = Enum.map(places, &%{&1 | x: round(&1.x / 20) * 20, y: round(&1.y / 20) * 20})

    if on_grid == places,
      do: on_change(change, context, room),
      else: {:ok, %{change | nodes: on_grid}}
  end

  def on_grid(change, context, room), do: on_change(change, context, room)

  defp column(graph, table, name) do
    with %{data: %{columns: columns}} <- Graph.node(graph, table),
         do: Enum.find(columns, &(&1.name == name))
  end

  # The canvas's menu: the app's own item for one table, and the canvas's own.
  def menu(%{kind: :node, nodes: [_table]}),
    do: [
      %{id: "add_column", label: "Add a column", icon: "plus"},
      :separator,
      :copy,
      :duplicate,
      :separator,
      :delete
    ]

  def menu(target), do: Hakushi.Menu.defaults(target)

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
        <span class="hint" data-selected={Enum.join(@selected, " ")} data-zoom={@zoom}>
          {if @selected == [], do: "Drag from a column's dot to a column of another table.", else: "Selected: " <> Enum.join(@selected, ", ")}
        </span>
        <form id="find" phx-submit="find" class="find">
          <input type="search" name="name" placeholder="Find a table" aria-label="Find a table" />
        </form>
        <button type="button" class="button" phx-click="show_all">Show all</button>
        <.link
          class="button"
          href={"/" <> HakushiDev.Layouts.qs(@query, if(@comments, do: %{}, else: %{"comments" => "1"}))}
        >
          {if @comments, do: "Hide comments", else: "Comments"}
        </.link>
        <.canvas_item :if={!@readonly} for="schema" item="table" class="button primary">
          <.icon name="plus" /> New table
        </.canvas_item>
      </:actions>
      <.canvas
        id="schema"
        graph={@graph}
        on_change={if @app_grid, do: &on_grid(&1, &2, @room), else: &on_change(&1, &2, @room)}
        on_select={&send(self(), {:selected, &1})}
        on_viewport={&send(self(), {:viewport, &1})}
        menu={&menu/1}
        on_menu={&send(self(), {:menu, &1, &2})}
        new_node={&new_node/2}
        issho={[instance: HakushiDev.Issho, document: @doc, follow: @follow]}
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
      <.comments :if={@comments} id="comments" room={@doc} class="comments-panel">
        <:place :let={%{place: place, default: default}}>
          {Hakushi.Issho.Place.label(place, @now, document: @doc) || default}
        </:place>
      </.comments>
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
     assign(socket,
       graph: HakushiDev.Store.get("workflow", socket.assigns.room),
       kinds: @kinds,
       run: nil,
       history: nil,
       then: nil
     )}
  end

  def on_change(change, %{result: result} = context, room) do
    HakushiDev.Store.put("workflow", room, result)
    HakushiDev.Store.record("workflow", room, change, context)
    :ok
  end

  # The versions of the workflow (Hakushi.History): a list of them, and the
  # workflow as it is now against the one chosen (the canvas's compare).
  @impl true
  def handle_event("history", _params, socket) do
    case socket.assigns.history do
      nil ->
        {:noreply,
         assign(socket,
           history: HakushiDev.Store.history("workflow", socket.assigns.room),
           then: nil
         )}

      _open ->
        {:noreply, assign(socket, history: nil, then: nil)}
    end
  end

  # A button of an edge's label (the canvas's :edge_label slot): the edge goes.
  def handle_event("drop_edge", %{"edge" => edge}, socket) do
    Hakushi.Live.change("workflow", Hakushi.Change.delete(edges: [edge]))
    {:noreply, socket}
  end

  def handle_event("then", %{"version" => version}, socket) do
    {:noreply, assign(socket, :then, String.to_integer(version))}
  end

  # A run of the workflow, step by step, shown with marks (Hakushi.Live.mark/3),
  # which are not saved: each step waits, runs (with its progress) and is
  # done, and the edges it takes run.
  def handle_event("run", _params, socket) do
    graph =
      Hakushi.Issho.graph(HakushiDev.Issho, topic("workflow", socket.assigns.room)) ||
        socket.assigns.graph

    order = run_order(graph)
    Hakushi.Live.clear_marks("workflow")
    Hakushi.Live.mark("workflow", order, status: :waiting)
    send(self(), :run)
    {:noreply, assign(socket, :run, %{graph: graph, order: order, progress: 0.0})}
  end

  @impl true
  def handle_info(:run, %{assigns: %{run: %{order: []}}} = socket),
    do: {:noreply, assign(socket, :run, nil)}

  def handle_info(
        :run,
        %{assigns: %{run: %{order: [id | rest], progress: progress} = run}} = socket
      ) do
    edges = for edge <- Hakushi.Graph.edges_of(run.graph, id), edge.source == id, do: edge.id

    run =
      if progress >= 1 do
        Hakushi.Live.mark("workflow", id, status: :done, progress: nil, badge: "✓")
        Hakushi.Live.mark_edges("workflow", edges, status: :done)
        %{run | order: rest, progress: 0.0}
      else
        Hakushi.Live.mark("workflow", id, status: :running, progress: progress)
        Hakushi.Live.mark_edges("workflow", edges, status: :running)
        %{run | progress: progress + 0.5}
      end

    Process.send_after(self(), :run, 150)
    {:noreply, assign(socket, :run, run)}
  end

  # The steps from the trigger on, each after the steps before it
  # (Hakushi.Graph's order of a flow).
  defp run_order(graph) do
    starts = for node <- Hakushi.Graph.nodes(graph), node.type == "trigger", do: node.id
    reached = MapSet.new(starts ++ Enum.flat_map(starts, &Hakushi.Graph.downstream(graph, &1)))

    case Hakushi.Graph.topological_sort(graph) do
      {:ok, order} -> Enum.filter(order, &MapSet.member?(reached, &1))
      {:error, _cycle} -> MapSet.to_list(reached)
    end
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
        <button type="button" class="button" phx-click="run" disabled={@run != nil or @history != nil}>Run</button>
        <button type="button" class="button" phx-click="history" aria-pressed={to_string(@history != nil)}>History</button>
        <span class="button primary"><.icon name="check" /> Published</span>
      </:actions>
      <aside :if={!@readonly} class="palette">
        <p>Drag a step onto the canvas, or press Enter on one.</p>
        <.canvas_item :for={{kind, {label, color}} <- Enum.sort(@kinds)} for="workflow" item={kind} style={"--kind: #{color}"}>
          <span><.icon name={kind} /></span>
          <div>{label}<small>{detail(kind)}</small></div>
        </.canvas_item>
      </aside>
      <aside :if={@history} class="palette versions" aria-label="Versions">
        <p :if={Hakushi.History.versions(@history) == []}>No changes yet. Move a step, then look again.</p>
        <button
          :for={v <- Enum.reverse(Hakushi.History.versions(@history))}
          type="button"
          class={["version", @then == v.version - 1 && "chosen"]}
          phx-click="then"
          phx-value-version={v.version - 1}
          data-version={v.version}
        >
          <strong>Before version {v.version}</strong>
          <small>{v.op} · {length(v.nodes)} nodes · {v.by || "the app"}</small>
        </button>
      </aside>
      <.canvas
        :if={@history && @then}
        id="workflow-then"
        graph={Hakushi.History.graph(@history)}
        compare={Hakushi.History.at(@history, @then)}
        background={:dots}
        label="The workflow now, against a version"
      >
        <:node :let={node}>
          <div class="step" data-status={node.data[:status] || node.data["status"]} style={"--kind: #{kind_color(node.type)}"}>
            <div class="body">
              <span class="kind"><.icon name={node.type} /></span>
              <div>
                <small>{kind_label(node.type)}</small>
                <strong>{node.data[:title] || node.data["title"]}</strong>
              </div>
            </div>
          </div>
        </:node>
      </.canvas>
      <.canvas
        :if={!(@history && @then)}
        id="workflow"
        graph={@graph}
        on_change={&on_change(&1, &2, @room)}
        new_node={&new_node/2}
        issho={[instance: HakushiDev.Issho, document: topic("workflow", @room)]}
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
        <:edge_label :let={edge}>
          <span :if={edge.label} class="way-label" data-way={edge.source_handle}>
            {edge.label}
            <button :if={!@readonly} type="button" phx-click="drop_edge" phx-value-edge={edge.id} aria-label={"Remove the way #{edge.label}"}>×</button>
          </span>
        </:edge_label>
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
  @moduledoc """
  A moodboard: notes that resize, swatches, a specimen, labelled arrows,
  ink (Hakushi.Kits.Ink): people draw on it with a pen, and an agent
  circles a node; and images (Hakushi.Kits.Images), dropped, pasted or
  picked. A frame opens (a double click on its title, its opener, ⌘↓) as
  a canvas of its own, its inside (`?frame=`), and ⌘↑ goes back.
  """
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Icons
  import HakushiDev.Layouts, only: [app: 1, qs: 2]
  import HakushiDev.Page, only: [topic: 2]

  alias Hakushi.Graph

  @kits [Hakushi.Kits.Ink, Hakushi.Kits.Images]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       graph: HakushiDev.Store.get("board", socket.assigns.room),
       frame: nil,
       kits: @kits
     )}
  end

  # A frame opened: its inside, as a canvas of its own.
  @impl true
  def handle_params(%{"frame" => id}, _uri, socket) do
    graph = HakushiDev.Store.get("board", socket.assigns.room)

    case Graph.node(graph, id) do
      %{type: "frame"} = frame ->
        {:noreply, assign(socket, frame: frame, inside: Graph.subgraph(graph, id))}

      _other ->
        {:noreply, push_patch(socket, to: "/board" <> qs(socket.assigns.query, %{}))}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     assign(socket, frame: nil, graph: HakushiDev.Store.get("board", socket.assigns.room))}
  end

  @impl true
  def handle_info({:open, id}, socket),
    do: {:noreply, push_patch(socket, to: "/board" <> qs(socket.assigns.query, %{"frame" => id}))}

  def handle_info(:up, socket),
    do: {:noreply, push_patch(socket, to: "/board" <> qs(socket.assigns.query, %{}))}

  def on_change(_change, %{result: result}, room) do
    HakushiDev.Store.put("board", room, result)
    :ok
  end

  # A change of a frame's inside: the board with that inside, and the
  # change, as the board's (Hakushi.Change.lift/2), in its room when someone
  # has it open.
  def on_inside(change, %{result: inside}, room, frame) do
    board = HakushiDev.Store.get("board", room)
    HakushiDev.Store.put("board", room, Graph.put_subgraph(board, frame.id, inside))

    _ =
      Hakushi.Issho.change(
        HakushiDev.Issho,
        topic("board", room),
        Hakushi.Change.lift(change, frame)
      )

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
  def render(%{frame: %{} = frame} = assigns) do
    assigns = assign(assigns, :title, frame.data.title)

    ~H"""
    <.app page={:board} me={@me} query={@query} title="Moodboard" crumb="Harbour Museum rebrand">
      <:actions>
        <.canvas_path>
          <:step patch={"/board" <> qs(@query, %{})}>Moodboard</:step>
          <:step>{@title}</:step>
        </.canvas_path>
        <span class="hint">⌘↑ goes back to the board.</span>
      </:actions>
      <.canvas
        id={"frame-" <> @frame.id}
        graph={@inside}
        on_change={&on_inside(&1, &2, @room, @frame)}
        on_up={fn _ -> send(self(), :up) end}
        new_node={&new_node/2}
        kits={@kits}
        readonly={@readonly}
        background={:cross}
        grid={20}
        snap
        rules={[loops: false]}
        label={@title}
      >
        <:node type="note" resizable :let={node}><.note node={node} /></:node>
        <:node type="frame" group resizable opens :let={node}><.frame node={node} /></:node>
        <:node type="title" :let={node}><.board_title node={node} /></:node>
        <:node type="swatches" :let={node}><.swatches node={node} /></:node>
        <:node type="specimen" :let={node}><.specimen node={node} /></:node>
      </.canvas>
    </.app>
    """
  end

  def render(assigns) do
    ~H"""
    <.app page={:board} me={@me} query={@query} title="Moodboard" crumb="Harbour Museum rebrand">
      <:actions>
        <span class="hint">Double-click the paper for a note. Draw with P, lasso with L; drop, paste or pick (I) images.</span>
        <.canvas_item :if={!@readonly} for="board" item="frame" class="button"><.icon name="frame" /> Frame</.canvas_item>
        <.canvas_item :if={!@readonly} for="board" item="note" class="button"><.icon name="note" /> Note</.canvas_item>
      </:actions>
      <.canvas
        id="board"
        graph={@graph}
        on_change={&on_change(&1, &2, @room)}
        on_open={&send(self(), {:open, &1.node})}
        client_tools={["ruler", "stamp"]}
        new_node={&new_node/2}
        kits={@kits}
        issho={[instance: HakushiDev.Issho, document: topic("board", @room), follow: @follow]}
        user={@me}
        readonly={@readonly}
        background={:cross}
        grid={20}
        snap
        papers={[:dots, :lines, :cross, :none, %{name: "iso", label: "Isometric"}]}
        rules={[loops: false]}
        label="The moodboard"
      >
        <:node type="note" resizable :let={node}><.note node={node} /></:node>
        <:node type="frame" group resizable opens :let={node}><.frame node={node} /></:node>
        <:node type="title" :let={node}><.board_title node={node} /></:node>
        <:node type="swatches" :let={node}><.swatches node={node} /></:node>
        <:node type="specimen" :let={node}><.specimen node={node} /></:node>
      </.canvas>
    </.app>
    """
  end

  defp note(assigns) do
    ~H"""
    <div class="note" data-tone={@node.data.tone}>
      <.handle kind={:both} side={:right} /><.handle kind={:both} side={:left} />
      {@node.data.text}
    </div>
    """
  end

  defp frame(assigns) do
    ~H"""
    <div class="frame"><span data-hakushi-drag>{@node.data.title} <.opener /></span></div>
    """
  end

  defp board_title(assigns) do
    ~H"""
    <div class="board-title"><strong>{@node.data.text}</strong><span>{@node.data.sub}</span></div>
    """
  end

  defp swatches(assigns) do
    ~H"""
    <div class="swatches">
      <.handle kind={:both} side={:left} /><.handle kind={:both} side={:right} />
      <small>{@node.data.title}</small>
      <ul>
        <li :for={{name, color} <- @node.data.colors}><span style={"--swatch: #{color}"}></span><em>{name}</em></li>
      </ul>
    </div>
    """
  end

  defp specimen(assigns) do
    ~H"""
    <div class="specimen">
      <.handle kind={:both} side={:left} /><.handle kind={:both} side={:right} /><.handle kind={:both} side={:bottom} />
      <small>Type</small>
      <b>{@node.data.sample}</b>
      <span>{@node.data.family} · {@node.data.note}</span>
    </div>
    """
  end
end

defmodule HakushiDev.WhiteboardLive do
  @moduledoc """
  A whiteboard of plain shapes (Hakushi.Kits.Shapes) and ink
  (Hakushi.Kits.Ink): drawn with the tools of the bar, styled from the
  panel beside the selection, shared.
  """
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Layouts, only: [app: 1]
  import HakushiDev.Page, only: [topic: 2]

  @kits [Hakushi.Kits.Shapes, Hakushi.Kits.Ink]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, graph: HakushiDev.Store.get("whiteboard", socket.assigns.room))}
  end

  def on_change(_change, %{result: result}, room) do
    HakushiDev.Store.put("whiteboard", room, result)
    :ok
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :kits, @kits)

    ~H"""
    <.app page={:whiteboard} me={@me} query={@query} title="Whiteboard" crumb="Release process">
      <:actions>
        <span class="hint">R, O, D and T draw shapes, A an arrow (between two shapes, an edge); double-click a shape to write in it.</span>
      </:actions>
      <.canvas
        id="whiteboard"
        graph={@graph}
        on_change={&on_change(&1, &2, @room)}
        kits={@kits}
        issho={[instance: HakushiDev.Issho, document: topic("whiteboard", @room), follow: @follow]}
        user={@me}
        readonly={@readonly}
        papers={true}
        label="The whiteboard"
      />
    </.app>
    """
  end
end

defmodule HakushiDev.SpecLive do
  @moduledoc """
  A design spec: a page of text with canvases in it, each in an embed
  frame (`canvas_embed/1`) and drawn with a built-in kit. The page scrolls
  past them; a frame goes full screen and back.
  """
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Layouts, only: [app: 1]

  alias Hakushi.Kits.{Flow, Notes, Schema}
  alias Phoenix.LiveView.JS

  @embeds [
    {"spec_schema", "Billing schema", [Schema]},
    {"spec_flow", "When an invoice is paid", [Flow]},
    {"spec_notes", "Open questions", [Notes]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    canvases =
      for {name, title, kits} <- @embeds,
          do: %{
            name: name,
            title: title,
            kits: kits,
            graph: HakushiDev.Store.get(name, socket.assigns.room)
          }

    {:ok, assign(socket, canvases: Map.new(canvases, &{&1.name, &1}), full: nil)}
  end

  def on_change(_change, %{result: result}, name, room) do
    HakushiDev.Store.put(name, room, result)
    :ok
  end

  @impl true
  def handle_event("full", %{"name" => name}, socket),
    do: {:noreply, assign(socket, full: if(socket.assigns.full == name, do: nil, else: name))}

  def handle_event("restore", _params, socket), do: {:noreply, assign(socket, full: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <.app page={:spec} me={@me} query={@query} title="Billing service" crumb="Design spec">
      <:actions>
        <span class="hint">Each canvas is a kit's. Draw in place; the full screen button opens one.</span>
      </:actions>
      <article class="spec" phx-window-keydown={@full && "restore"} phx-key="Escape">
        <h2>Data model</h2>
        <p>
          A customer has invoices; an invoice has lines. Money is stored in minor units, with its
          currency on the invoice. Draw a foreign key from a column to a column of the same type.
        </p>
        <.spec_embed canvas={@canvases["spec_schema"]} full={@full} readonly={@readonly} room={@room} />
        <h2>When an invoice is paid</h2>
        <p>
          The payment provider calls us once per paid invoice. Large invoices wait for finance;
          the others get their receipt at once.
        </p>
        <.spec_embed canvas={@canvases["spec_flow"]} full={@full} readonly={@readonly} room={@room} />
        <h2>Open questions</h2>
        <p>Write on a note, give it a colour, or join two with an arrow.</p>
        <.spec_embed canvas={@canvases["spec_notes"]} full={@full} readonly={@readonly} room={@room} />
        <p class="end">That is the whole of it, for now.</p>
      </article>
    </.app>
    """
  end

  attr :canvas, :map, required: true
  attr :full, :string, default: nil
  attr :readonly, :boolean, default: false
  attr :room, :string, default: nil

  defp spec_embed(assigns) do
    assigns = assign(assigns, :is_full, assigns.full == assigns.canvas.name)

    ~H"""
    <div class={["spec-embed", @is_full && "full"]}>
      <div :if={@is_full} class="spec-scrim" phx-click="restore"></div>
      <.canvas_embed
        title={@canvas.title}
        icon={hd(@canvas.kits).icon()}
        subtitle={hd(@canvas.kits).title(Hakushi.Messages.for_locale("en"))}
        for={@canvas.name}
        kits={@canvas.kits}
        readonly={@readonly}
        full={@is_full}
        on_full={JS.push("full", value: %{name: @canvas.name})}
      >
        <.canvas
          id={@canvas.name}
          graph={@canvas.graph}
          kits={@canvas.kits}
          on_change={&on_change(&1, &2, @canvas.name, @room)}
          readonly={@readonly}
          wheel={:scroll}
          refit
          minimap={@is_full}
          label={@canvas.title}
        />
      </.canvas_embed>
    </div>
    """
  end
end

defmodule HakushiDev.DatabaseLive do
  @moduledoc """
  A database read from a server, as Lotus shows one (`?n=` tables, 120
  unless given): the tables are facts, so people only arrange them
  (`readonly={:arrange}`), and the canvas lays them out as it opens
  (`tidy`), by forces unless `?layout=` says another way. Nothing is kept:
  a reload lays them out again.
  """
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Layouts, only: [app: 1]

  @impl true
  def mount(params, _session, socket) do
    n = params |> Map.get("n", "120") |> String.to_integer() |> min(5_000) |> max(2)

    layout =
      if params["layout"] in ~w(right down force grid),
        do: String.to_existing_atom(params["layout"]),
        else: :force

    graph = HakushiDev.Seeds.database(n)
    {:ok, assign(socket, n: n, way: layout, keys: map_size(graph.edges), graph: graph)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.app page={:database} me={@me} query={@query} title="A database" crumb={"public · #{@n} tables · #{@keys} foreign keys"}>
      <:actions>
        <span class="hint">Read from the server: drag tables, or tidy up another way. Nothing is kept.</span>
      </:actions>
      <.canvas
        id="database"
        graph={@graph}
        kits={[Hakushi.Kits.Schema]}
        readonly={:arrange}
        tidy
        fit={:readable}
        layout={@way}
        label="The tables of the database"
      />
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
  use Issho.MCP,
    name: "hakushi-dev",
    version: "0.0.0",
    tools: Issho.Tools.room() ++ Hakushi.Issho.tools()
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

defmodule HakushiDev.ColoursLive do
  @moduledoc """
  Every colour of the kits on one canvas: the notes, the shapes, the pen
  and the highlighter, a table's keys and a condition. To see them in each
  theme (`?sumi=smoke`), with a selection.
  """
  use Phoenix.LiveView

  import Hakushi.Components
  import HakushiDev.Layouts, only: [app: 1]

  alias Hakushi.Kits.{Flow, Ink, Notes, Schema, Shapes}

  @kits [Notes, Shapes, Ink, Schema, Flow]

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, graph: graph())}

  def on_change(_change, %{result: result}) do
    send(self(), {:graph, result})
    :ok
  end

  @impl true
  def handle_info({:graph, graph}, socket), do: {:noreply, assign(socket, graph: graph)}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :kits, @kits)

    ~H"""
    <.app page={:colours} me={@me} query={@query} title="Every colour" crumb="Of the kits">
      <:actions>
        <span class="hint">Each theme under Sumi, in the panel: the colours, and a selection, in its accent.</span>
      </:actions>
      <.canvas id="colours" graph={@graph} on_change={&on_change/2} kits={@kits} readonly={@readonly} label="Every colour" />
    </.app>
    """
  end

  defp graph do
    notes =
      for {color, i} <- Enum.with_index(Notes.colors()),
          do: %{
            id: "note-" <> color,
            type: "note",
            x: i * 180,
            y: 0,
            width: 160,
            height: 100,
            data: %{"text" => color, "color" => color}
          }

    shapes =
      for {color, i} <- Enum.with_index(Shapes.colors()) do
        style = %{"text" => color, "fill" => color, "stroke" => color}
        Map.put(Shapes.shape("rect", [i * 130, 140, 110, 64], style), :id, "shape-" <> color)
      end

    strokes =
      for {tool, y} <- [{"pen", 250}, {"highlighter", 320}],
          {color, i} <- Enum.with_index(Ink.colors()) do
        x = i * 130
        points = for t <- 0..10, do: [x + t * 10, y + 14 * :math.sin(t / 10 * 2 * :math.pi())]
        {:ok, stroke} = Ink.stroke(points, tool: tool, color: color)
        Map.put(stroke, :id, "#{tool}-#{color}")
      end

    Hakushi.Graph.new(
      nodes:
        notes ++
          shapes ++
          strokes ++
          [
            %{
              id: "table",
              type: "schema-table",
              x: 960,
              y: 0,
              data: %{
                "name" => "invoices",
                "columns" => [
                  %{"id" => "i1", "name" => "id", "type" => "uuid", "key" => "pk"},
                  %{"id" => "i2", "name" => "customer_id", "type" => "uuid", "key" => "fk"},
                  %{"id" => "i3", "name" => "total", "type" => "money", "key" => nil}
                ]
              }
            },
            %{
              id: "condition",
              type: "flow-condition",
              x: 960,
              y: 200,
              data: %{"title" => "Over €1,000?", "detail" => ""}
            },
            %{
              id: "step",
              type: "flow-step",
              x: 960,
              y: 320,
              data: %{"title" => "Send the receipt", "detail" => "Email"}
            }
          ],
      edges: [%{source: "note-yellow", target: "note-rose"}]
    )
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
      live("/whiteboard", HakushiDev.WhiteboardLive)
      live("/spec", HakushiDev.SpecLive)
      live("/scale", HakushiDev.ScaleLive)
      live("/database", HakushiDev.DatabaseLive)
      live("/colours", HakushiDev.ColoursLive)
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
  # Issho's script and theme, from its Hex package: its hooks (comments).
  plug(Plug.Static, at: "/vendor/issho", from: {:issho, "priv/static"})
  # The images people add (Storehouse.Local), and the photos of the tests, by their address.
  plug(Storehouse.Local.Plug)
  plug(Plug.Static, at: "/fixtures", from: Path.expand("test/fixtures/images", __DIR__))

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
        # The room of each shared canvas, its people and their cursors. The
        # canvases last as their rooms do (`store: :none`); the comments are
        # kept in the store, in memory while the server runs.
        {Issho.Store.Memory, name: HakushiDev.CollabStore},
        {Issho,
         name: HakushiDev.Issho,
         pubsub: HakushiDev.PubSub,
         endpoint: HakushiDev.Endpoint,
         policy: HakushiDev.Collaboration,
         store: {Issho.Store.Memory, HakushiDev.CollabStore}},
        HakushiDev.Endpoint
      ],
      strategy: :one_for_one
    )

  IO.puts("Hakushi development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
