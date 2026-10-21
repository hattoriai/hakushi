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
  """

  use Hakushi.Kit

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
end
