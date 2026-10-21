defmodule Hakushi.Kits.Flow do
  @moduledoc """
  The kit of a flow: a trigger that starts it, steps, and conditions with
  two ways out, joined by edges in the order they run.

  Its nodes are of types `"flow-trigger"`, `"flow-step"` and
  `"flow-condition"`, with the data:

      %{"title" => "Invoice paid", "detail" => "Stripe webhook"}

  A trigger has a way out and no way in; a step one of each; a condition
  a way in and two ways out, with the handles `"yes"` and `"no"`. People
  write the title and the detail in place.

  In Markdown, a flow is a Mermaid flowchart: a trigger is a stadium
  (`(["..."])`), a condition a rhombus (`{"..."}`), a step a box, and the
  ways out of a condition are labelled Yes and No. `from_markdown/1`
  reads it back, and reads flowcharts people write.
  """

  use Hakushi.Kit

  alias Hakushi.{Graph, Mermaid}

  @kinds %{
    "flow-trigger" => {"trigger", "zap"},
    "flow-step" => {"step", "square-play"},
    "flow-condition" => {"condition", "split"}
  }

  @impl true
  def name, do: "flow"

  @impl true
  def title(messages), do: messages["kitFlow"]

  @impl true
  def icon, do: "workflow"

  @impl true
  def canvas, do: [background: :dots, layout: :right, rules: [loops: false, cycles: false]]

  @impl true
  def types, do: ["flow-trigger", "flow-step", "flow-condition"]

  @impl true
  def elements(messages) do
    for type <- types() do
      {word, icon} = @kinds[type]
      %{item: word, label: messages[word], icon: icon}
    end
  end

  @impl true
  def new_node(item, {x, y}, messages) do
    word = if item in ["trigger", "condition"], do: item, else: "step"

    %{
      type: "flow-" <> word,
      x: x,
      y: y,
      data: %{"title" => messages[word], "detail" => ""}
    }
  end

  @impl true
  def node(assigns) do
    {word, icon} = @kinds[assigns.node.type]

    assigns =
      assign(assigns,
        word: word,
        icon: icon,
        title: get(assigns.node.data, "title"),
        detail: get(assigns.node.data, "detail")
      )

    ~H"""
    <div class="hakushi-kit-step" data-kind={@word}>
      <.handle :if={@word != "trigger"} kind={:target} side={:left} />
      <span class="hakushi-kit-step-icon"><.icon name={@icon} size={15} /></span>
      <span class="hakushi-kit-step-text">
        <span class="hakushi-kit-step-kind">{@messages[@word]}</span>
        <input
          :if={!@readonly}
          class="hakushi-kit-field hakushi-kit-step-title"
          value={@title}
          aria-label={@messages["title"]}
          phx-blur="hakushi:edit"
          phx-keydown="hakushi:edit"
          phx-key="Enter"
          phx-target={@target}
          phx-value-node={@node.id}
          phx-value-action="title"
        />
        <span :if={@readonly} class="hakushi-kit-step-title">{@title}</span>
        <input
          :if={!@readonly}
          class="hakushi-kit-field hakushi-kit-step-detail"
          value={@detail}
          placeholder={@messages["detail"]}
          aria-label={@messages["detail"]}
          phx-blur="hakushi:edit"
          phx-keydown="hakushi:edit"
          phx-key="Enter"
          phx-target={@target}
          phx-value-node={@node.id}
          phx-value-action="detail"
        />
        <span :if={@readonly and @detail not in [nil, ""]} class="hakushi-kit-step-detail">
          {@detail}
        </span>
      </span>
      <.handle :if={@word != "condition"} kind={:source} side={:right} />
      <span :if={@word == "condition"} class="hakushi-kit-ways">
        <span class="hakushi-kit-way">
          {@messages["yes"]}<.handle id="yes" kind={:source} side={:right} />
        </span>
        <span class="hakushi-kit-way">
          {@messages["no"]}<.handle id="no" kind={:source} side={:right} />
        </span>
      </span>
    </div>
    """
  end

  @impl true
  def edit(action, %{"value" => value}, data) when action in ["title", "detail"],
    do: {:ok, Map.put(data, action, String.slice(String.trim(to_string(value)), 0, 200))}

  def edit(_action, _params, _data), do: :error

  @shapes %{
    "flow-trigger" => {"([", "])"},
    "flow-condition" => {"{", "}"},
    "flow-step" => {"[", "]"}
  }

  @impl true
  def to_markdown(graph) do
    case Enum.filter(Graph.nodes(graph), &(&1.type in types())) do
      [] ->
        nil

      nodes ->
        ids = Mermaid.ids(nodes)

        edges =
          Enum.filter(
            Graph.edges(graph),
            &(Map.has_key?(ids, &1.source) and Map.has_key?(ids, &1.target))
          )

        body =
          ["flowchart LR"] ++
            Enum.map(nodes, &node_line(&1, ids)) ++
            Enum.map(edges, &edge_line(&1, ids)) ++
            [Mermaid.places(nodes, ids), Mermaid.edge_places(edges, ids)]

        Mermaid.fence(name(), Enum.join(body, "\n"))
    end
  end

  defp node_line(node, ids) do
    {open, close} = @shapes[node.type]
    title = get(node.data, "title") || ""
    detail = get(node.data, "detail") || ""
    text = if detail == "", do: title, else: title <> "\n" <> detail
    "  " <> ids[node.id] <> open <> Mermaid.label(text) <> close
  end

  defp edge_line(edge, ids) do
    label = edge.label || way(edge.source_handle)
    arrow = if label, do: "-->|" <> String.replace(label, "|", "/") <> "|", else: "-->"
    "  #{ids[edge.source]} #{arrow} #{ids[edge.target]}"
  end

  defp way("yes"), do: "Yes"
  defp way("no"), do: "No"
  defp way(_handle), do: nil

  @impl true
  def from_markdown(text) do
    with {:ok, nodes, edges} <- Mermaid.flowchart(text) do
      places = Mermaid.read_places(text)

      nodes = Enum.map(nodes, &flow_node/1)

      edges = Mermaid.read_edges(text) || ways(nodes, edges)
      {:ok, Mermaid.graph(nodes, edges, places)}
    end
  end

  defp flow_node(node) do
    {title, detail} =
      case String.split(node.text || node.m, "\n", parts: 2) do
        [title, detail] -> {title, detail}
        [title] -> {title, ""}
      end

    %{m: node.m, type: flow_type(node.shape), data: %{"title" => title, "detail" => detail}}
  end

  defp flow_type(:stadium), do: "flow-trigger"
  defp flow_type(:rhombus), do: "flow-condition"
  defp flow_type(_shape), do: "flow-step"

  # The ways out of a condition: a Yes or No label, else the first is yes
  # and the second no.
  defp ways(nodes, edges) do
    conditions = for %{type: "flow-condition", m: m} <- nodes, into: MapSet.new(), do: m

    {edges, _count} =
      Enum.map_reduce(edges, %{}, fn edge, count ->
        if MapSet.member?(conditions, edge.from) do
          n = Map.get(count, edge.from, 0)
          handle = way_of(edge.label) || Enum.at(["yes", "no"], n)
          label = if way_of(edge.label), do: nil, else: edge.label

          {%{from: edge.from, to: edge.to, source_handle: handle, label: label},
           Map.put(count, edge.from, n + 1)}
        else
          {Map.take(edge, [:from, :to, :label]), count}
        end
      end)

    edges
  end

  defp way_of(nil), do: nil

  defp way_of(label) do
    case String.downcase(String.trim(label)) do
      word when word in ["yes", "true", "y"] -> "yes"
      word when word in ["no", "false", "n"] -> "no"
      _other -> nil
    end
  end
end
