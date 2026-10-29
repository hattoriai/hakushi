defmodule Hakushi.Mermaid do
  @moduledoc """
  Helpers for kits that write their canvas as a Mermaid diagram in
  Markdown, and read it back (`c:Hakushi.Kit.to_markdown/1`,
  `c:Hakushi.Kit.from_markdown/1`).

  Mermaid says what is on a canvas, not where: so that a canvas comes back
  as it was, `places/2` writes each node's place, size and id in comments
  (`%% hakushi {...}`), which Mermaid renderers leave out, and
  `read_places/1` reads them back. A diagram with no such comments (one a
  person wrote) gets a layout of its own (`layers/2`).

      ```mermaid
      %% hakushi kit=flow
      flowchart LR
        n1(["Invoice paid"])
        n2["Send the receipt"]
        n1 --> n2
      %% hakushi {"m":"n1","id":"paid","x":0,"y":40}
      %% hakushi {"m":"n2","id":"receipt","x":300,"y":40}
      ```
  """

  alias Hakushi.{Graph, Node}

  @fence ~r/\A\s*```+\s*mermaid[^\n]*\n(.*?)\n\s*```+\s*\z/s

  @doc "Puts a diagram in a fenced `mermaid` block, after the kit's marker."
  @spec fence(String.t(), String.t()) :: String.t()
  def fence(kit, body),
    do: "```mermaid\n%% hakushi kit=#{kit}\n" <> String.trim_trailing(body) <> "\n```"

  @doc """
  The diagram of a Markdown text: the body of its fenced `mermaid` block,
  or the text itself.
  """
  @spec unfence(String.t()) :: String.t()
  def unfence(text) do
    case Regex.run(@fence, text) do
      [_all, body] -> body
      nil -> text
    end
  end

  @doc "The kit a diagram names (`%% hakushi kit=schema`), or `nil`."
  @spec kit(String.t()) :: String.t() | nil
  def kit(text) do
    case Regex.run(~r/^\s*%%\s*hakushi\s+kit=([\w-]+)/m, text) do
      [_line, name] -> name
      nil -> nil
    end
  end

  @doc """
  The lines of a diagram, trimmed, without its comments and blank lines.
  """
  @spec lines(String.t()) :: [String.t()]
  def lines(text) do
    text
    |> unfence()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "%%")))
  end

  @doc """
  The comments that keep the places of `nodes`: one for each, with its
  Mermaid id (from `ids`, node id to Mermaid id), its own id, its place and
  size, and `extra` data of the kit's (a map from node id to a map).
  """
  @spec places([Node.t()], %{String.t() => String.t()}, map()) :: String.t()
  def places(nodes, ids, extra \\ %{}) do
    Enum.map_join(nodes, "\n", fn node ->
      place =
        %{"m" => ids[node.id], "id" => node.id, "x" => node.x, "y" => node.y}
        |> put_present("w", node.width)
        |> put_present("h", node.height)
        |> put_present("parent", node.parent)
        |> Map.merge(Map.get(extra, node.id, %{}))

      "%% hakushi " <> JSON.encode!(place)
    end)
  end

  @doc "The places a diagram keeps, by Mermaid id."
  @spec read_places(String.t()) :: %{String.t() => map()}
  def read_places(text) do
    for [json] <- Regex.scan(~r/^\s*%%\s*hakushi\s+(\{.*\})\s*$/m, text, capture: :all_but_first),
        {:ok, %{"m" => m} = place} <- [JSON.decode(json)],
        into: %{},
        do: {m, place}
  end

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  @doc """
  Mermaid ids for nodes: `n1`, `n2`, ... in their order (a node's own id
  may have characters Mermaid does not take).
  """
  @spec ids([Node.t()]) :: %{String.t() => String.t()}
  def ids(nodes),
    do: nodes |> Enum.with_index(1) |> Map.new(fn {node, i} -> {node.id, "n#{i}"} end)

  @doc """
  A label for Mermaid, in double quotes: its quotes and its line breaks
  written as Mermaid writes them.
  """
  @spec label(String.t() | nil) :: String.t()
  def label(text) do
    escaped =
      (text || "")
      |> String.replace("#", "#35;")
      |> String.replace("\"", "#quot;")
      |> String.replace(~r/\r?\n/, "<br>")

    ~s("#{escaped}")
  end

  @doc "A label read from Mermaid: without its quotes, with its entities and line breaks."
  @spec unlabel(String.t()) :: String.t()
  def unlabel(text) do
    text
    |> String.trim()
    |> String.trim("\"")
    |> String.replace(~r/<br\s*\/?>/i, "\n")
    |> String.replace("#quot;", "\"")
    |> String.replace("#35;", "#")
  end

  @doc """
  Places for nodes that a diagram did not keep: in layers along the edges
  (a node right of the nodes it comes from), from left to right. `nodes`
  are ids in their order, `edges` pairs of ids.
  """
  @spec layers([String.t()], [{String.t(), String.t()}], keyword()) :: %{
          String.t() => {number(), number()}
        }
  def layers(nodes, edges, opts \\ []) do
    dx = Keyword.get(opts, :dx, 320)
    dy = Keyword.get(opts, :dy, 160)
    incoming = Enum.group_by(edges, &elem(&1, 1), &elem(&1, 0))

    depth =
      Enum.reduce(nodes, %{}, fn id, acc ->
        Map.put(acc, id, depth(id, incoming, %{}))
      end)

    nodes
    |> Enum.group_by(&depth[&1])
    |> Enum.flat_map(fn {layer, ids} ->
      ids |> Enum.with_index() |> Enum.map(fn {id, row} -> {id, {layer * dx, row * dy}} end)
    end)
    |> Map.new()
  end

  # The longest way back to a node with nothing before it (a cycle stops).
  defp depth(id, incoming, seen) do
    case Map.get(incoming, id, []) |> Enum.reject(&Map.has_key?(seen, &1)) do
      [] -> 0
      from -> 1 + Enum.max(Enum.map(from, &depth(&1, incoming, Map.put(seen, id, true))))
    end
  end

  @doc """
  A graph of nodes and edges read from a diagram: each node at its kept
  place, or at a place of `layers/3`.
  """
  @spec graph([map()], [map()], %{String.t() => map()}) :: Graph.t()
  def graph(nodes, edges, places) do
    missing = Enum.reject(nodes, &Map.has_key?(places, &1.m))
    laid = layers(Enum.map(missing, & &1.m), Enum.map(edges, &{&1.from, &1.to}))
    ids = Map.new(nodes, &{&1.m, (places[&1.m] || %{})["id"] || &1.m})

    graph_nodes =
      Enum.map(nodes, fn node ->
        place = places[node.m]
        {x, y} = if place, do: {place["x"], place["y"]}, else: laid[node.m]

        %{id: ids[node.m], type: node.type, x: x, y: y, data: node.data}
        |> put_place(:width, place && place["w"])
        |> put_place(:height, place && place["h"])
      end)

    graph_edges =
      Enum.map(edges, fn edge ->
        Map.merge(%{source: ids[edge.from], target: ids[edge.to]}, Map.drop(edge, [:from, :to]))
      end)

    Graph.new(nodes: graph_nodes, edges: graph_edges)
  end

  defp put_place(node, _key, nil), do: node
  defp put_place(node, key, value), do: Map.put(node, key, value)

  @doc """
  The comments that keep `edges` as they are (their handles, label, path,
  marker): one for each, with the Mermaid ids of its ends (`ids`).
  """
  @spec edge_places([Hakushi.Edge.t()], %{String.t() => String.t()}) :: String.t()
  def edge_places(edges, ids) do
    Enum.map_join(edges, "\n", fn edge ->
      place =
        %{"from" => ids[edge.source], "to" => ids[edge.target], "id" => edge.id}
        |> put_present("sh", edge.source_handle)
        |> put_present("th", edge.target_handle)
        |> put_present("label", edge.label)
        |> put_present("path", if(edge.path != "bezier", do: edge.path))
        |> put_present("marker", if(edge.marker != "arrow", do: edge.marker))
        |> put_present("animated", if(edge.animated, do: true))
        |> put_present("points", if(edge.points != [], do: edge.points))

      "%% hakushi edge " <> JSON.encode!(place)
    end)
  end

  @doc """
  The edges a diagram keeps (`edge_places/2`), as maps for `graph/3`, or
  `nil` when it keeps none.
  """
  @spec read_edges(String.t()) :: [map()] | nil
  def read_edges(text) do
    edges =
      for [json] <-
            Regex.scan(~r/^\s*%%\s*hakushi\s+edge\s+(\{.*\})\s*$/m, text, capture: :all_but_first),
          {:ok, %{"from" => from, "to" => to} = edge} <- [JSON.decode(json)] do
        %{from: from, to: to}
        |> put_present(:id, edge["id"])
        |> put_present(:source_handle, edge["sh"])
        |> put_present(:target_handle, edge["th"])
        |> put_present(:label, edge["label"])
        |> put_present(:path, edge["path"])
        |> put_present(:marker, edge["marker"])
        |> put_present(:animated, edge["animated"])
        |> put_present(:points, edge["points"])
      end

    if edges == [], do: nil, else: edges
  end

  @node ~r/^([A-Za-z0-9_-]+)(\(\[.*?\]\)|\(\(.*?\)\)|\[\[.*?\]\]|\{.*?\}|\[.*?\]|\(.*?\))?(?::::([\w-]+))?$/
  @arrow ~r/\s*(?:-->|---|-\.->|==>|-\.-|===)(?:\|([^|]*)\|)?\s*/

  @doc """
  The nodes and edges of a Mermaid flowchart: `{:ok, nodes, edges}`, with
  each node a map of its Mermaid id (`m`), `shape` (`:stadium` for
  `([...])`, `:circle` for `((...))`, `:rhombus` for `{...}`, `:round` for
  `(...)`, `:trapezoid` for `[/...\\]`, `:box` for the others), `text` and
  `class` (`:::name`), in the order they come; and each edge a map of
  `from`, `to` and `label`. `:error` for a text that is not a
  flowchart.

  It reads what kits write and what people commonly write (`a --> b`,
  `a -->|label| b`, `a -- label --> b`, chains, shapes on the way), not
  every form of Mermaid.
  """
  @spec flowchart(String.t()) :: {:ok, [map()], [map()]} | :error
  def flowchart(text) do
    case lines(text) do
      [head | statements] ->
        if Regex.match?(~r/^(flowchart|graph)\b/, head),
          do: {:ok, statements} |> read_flowchart(),
          else: :error

      [] ->
        :error
    end
  end

  defp read_flowchart({:ok, statements}) do
    {nodes, edges} =
      Enum.reduce(statements, {[], []}, fn statement, acc ->
        if Regex.match?(
             ~r/^(classDef|class|style|linkStyle|subgraph|end|direction)\b/,
             statement
           ),
           do: acc,
           else: read_statement(statement, acc)
      end)

    {:ok, Enum.reverse(nodes), Enum.reverse(edges)}
  end

  defp read_statement(statement, {nodes, edges}) do
    # `a -- label --> b` is `a -->|label| b`.
    statement = Regex.replace(~r/--\s+([^>|]+?)\s+-->/, statement, "-->|\\1|")
    parts = Regex.split(@arrow, statement, include_captures: true, trim: true)

    {refs, labels} =
      Enum.reduce(parts, {[], []}, fn part, {refs, labels} ->
        case Regex.run(@arrow, part) do
          [^part | label] when part != "" ->
            {refs, [List.first(label) |> then(&(&1 && String.trim(&1))) | labels]}

          _node ->
            {[part | refs], labels}
        end
      end)

    refs = Enum.reverse(refs)
    labels = Enum.reverse(labels)

    {nodes, ids} =
      Enum.reduce(refs, {nodes, []}, fn ref, {nodes, ids} ->
        case read_node(String.trim(ref)) do
          nil -> {nodes, ids}
          node -> {add_node(nodes, node), [node.m | ids]}
        end
      end)

    ids = Enum.reverse(ids)

    edges =
      ids
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.zip(labels ++ List.duplicate(nil, length(ids)))
      |> Enum.reduce(edges, fn {[from, to], label}, edges ->
        [
          %{from: from, to: to, label: if(label in [nil, ""], do: nil, else: unlabel(label))}
          | edges
        ]
      end)

    {nodes, edges}
  end

  defp read_node(ref) do
    case Regex.run(@node, ref) do
      nil ->
        nil

      [_all, m] ->
        %{m: m, shape: nil, text: nil, class: nil}

      [_all, m, shape | class] ->
        {kind, inner} = shape(shape)
        %{m: m, shape: kind, text: inner && unlabel(inner), class: List.first(class)}
    end
  end

  defp shape(""), do: {nil, nil}
  defp shape("([" <> rest), do: {:stadium, String.slice(rest, 0..-3//1)}
  defp shape("((" <> rest), do: {:circle, String.slice(rest, 0..-3//1)}
  defp shape("[[" <> rest), do: {:box, String.slice(rest, 0..-3//1)}
  defp shape("{" <> rest), do: {:rhombus, String.slice(rest, 0..-2//1)}

  defp shape("[/" <> rest) do
    if String.ends_with?(rest, "\\]"),
      do: {:trapezoid, String.slice(rest, 0..-3//1)},
      else: {:box, "/" <> String.slice(rest, 0..-2//1)}
  end

  defp shape("[" <> rest), do: {:box, String.slice(rest, 0..-2//1)}
  defp shape("(" <> rest), do: {:round, String.slice(rest, 0..-2//1)}

  # A node said again keeps what it had; a shape or class given later wins.
  defp add_node(nodes, node) do
    case Enum.find_index(nodes, &(&1.m == node.m)) do
      nil ->
        [%{node | shape: node.shape || :box} | nodes]

      i ->
        List.update_at(nodes, i, fn old ->
          %{
            old
            | shape: if(node.shape, do: node.shape, else: old.shape),
              text: node.text || old.text,
              class: node.class || old.class
          }
        end)
    end
  end
end
