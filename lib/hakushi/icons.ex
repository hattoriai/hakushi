defmodule Hakushi.Icons do
  @moduledoc """
  The icons of the kits and of the embed frame: Lucide icons
  (https://lucide.dev, ISC licence), drawn with strokes of `currentColor`,
  as Kotoba's toolbar draws its own.

      <Hakushi.Icons.icon name="database" />

  A kit's `icon/0` and its elements' icons are names of this set
  (`names/0`).
  """

  use Phoenix.Component

  @shapes %{
    "database" =>
      ~s(<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5V19A9 3 0 0 0 21 19V5"/><path d="M3 12A9 3 0 0 0 21 12"/>),
    "table" =>
      ~s(<path d="M12 3v18"/><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/>),
    "workflow" =>
      ~s(<rect width="8" height="8" x="3" y="3" rx="2"/><path d="M7 11v4a2 2 0 0 0 2 2h4"/><rect width="8" height="8" x="13" y="13" rx="2"/>),
    "zap" =>
      ~s(<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>),
    "square-play" =>
      ~s(<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 9.003a1 1 0 0 1 1.517-.859l4.997 2.997a1 1 0 0 1 0 1.718l-4.997 2.997A1 1 0 0 1 9 14.996z"/>),
    "split" =>
      ~s(<path d="M16 3h5v5"/><path d="M8 3H3v5"/><path d="M12 22v-8.3a4 4 0 0 0-1.172-2.872L3 3"/><path d="m15 9 6-6"/>),
    "sticky-note" =>
      ~s(<path d="M16 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8Z"/><path d="M15 3v4a2 2 0 0 0 2 2h4"/>),
    "shapes" =>
      ~s(<path d="M8.3 10a.7.7 0 0 1-.626-1.079L11.4 3a.7.7 0 0 1 1.198-.043L16.3 8.9a.7.7 0 0 1-.572 1.1Z"/><rect x="3" y="14" width="7" height="7" rx="1"/><circle cx="17.5" cy="17.5" r="3.5"/>),
    "flag" =>
      ~s(<path d="M4 22V4a1 1 0 0 1 .4-.8A6 6 0 0 1 8 2c3 0 5 2 7.333 2q2 0 3.067-.8A1 1 0 0 1 20 4v10a1 1 0 0 1-.4.8A6 6 0 0 1 16 16c-3 0-5-2-8-2a6 6 0 0 0-4 1.528"/>),
    "key" =>
      ~s(<path d="m15.5 7.5 2.3 2.3a1 1 0 0 0 1.4 0l2.1-2.1a1 1 0 0 0 0-1.4L19 4"/><path d="m21 2-9.6 9.6"/><circle cx="7.5" cy="15.5" r="5.5"/>),
    "link" =>
      ~s(<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>),
    "maximize" =>
      ~s(<path d="M15 3h6v6"/><path d="m21 3-7 7"/><path d="m3 21 7-7"/><path d="M9 21H3v-6"/>),
    "minimize" =>
      ~s(<path d="m14 10 7-7"/><path d="M20 10h-6V4"/><path d="m3 21 7-7"/><path d="M4 14h6v6"/>),
    "plus" => ~s(<path d="M5 12h14"/><path d="M12 5v14"/>),
    "square" => ~s(<rect width="18" height="18" x="3" y="3" rx="2"/>),
    "circle" => ~s(<circle cx="12" cy="12" r="10"/>),
    "diamond" =>
      ~s(<path d="M2.7 10.3a2.41 2.41 0 0 0 0 3.41l7.59 7.59a2.41 2.41 0 0 0 3.41 0l7.59-7.59a2.41 2.41 0 0 0 0-3.41l-7.59-7.59a2.41 2.41 0 0 0-3.41 0Z"/>),
    "triangle" =>
      ~s(<path d="M13.73 4a2 2 0 0 0-3.46 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/>),
    "type" =>
      ~s(<path d="M12 4v16"/><path d="M4 7V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v2"/><path d="M9 20h6"/>),
    "arrow" => ~s(<path d="M13 5h6v6"/><path d="M19 5 5 19"/>),
    "pen" =>
      ~s(<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/>),
    "highlighter" =>
      ~s(<path d="m9 11-6 6v3h9l3-3"/><path d="m22 12-4.6 4.6a2 2 0 0 1-2.8 0l-5.2-5.2a2 2 0 0 1 0-2.8L14 4"/>),
    "eraser" =>
      ~s(<path d="M21 21H8a2 2 0 0 1-1.42-.587l-3.994-3.999a2 2 0 0 1 0-2.828l10-10a2 2 0 0 1 2.829 0l5.999 6a2 2 0 0 1 0 2.828L12.834 21"/><path d="m5.082 11.09 8.828 8.828"/>),
    "lasso" =>
      ~s(<path d="M7 22a5 5 0 0 1-2-4"/><path d="M3.3 14A6.8 6.8 0 0 1 2 10c0-4.4 4.5-8 10-8s10 3.6 10 8-4.5 8-10 8a12 12 0 0 1-5-1"/><path d="M5 18a2 2 0 1 0 0-4 2 2 0 0 0 0 4z"/>),
    "image" =>
      ~s(<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>),
    "x" => ~s(<path d="M18 6 6 18"/><path d="m6 6 12 12"/>)
  }

  @doc "The names of the icons."
  @spec names() :: [String.t()]
  def names, do: @shapes |> Map.keys() |> Enum.sort()

  @doc false
  # An icon as the markup of its SVG, for the browser to put in place (an
  # item of the canvas's menu).
  @spec svg(String.t(), pos_integer()) :: String.t()
  def svg(name, size \\ 16) do
    ~s(<svg class="hakushi-icon" viewBox="0 0 24 24" width="#{size}" height="#{size}" fill="none" ) <>
      ~s(stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ) <>
      ~s(aria-hidden="true">#{Map.fetch!(@shapes, name)}</svg>)
  end

  @doc "Renders an icon of this set."
  attr :name, :string, required: true, doc: "a name of `names/0`"
  attr :size, :integer, default: 16
  attr :class, :any, default: nil

  def icon(assigns) do
    assigns = assign(assigns, :body, Phoenix.HTML.raw(Map.fetch!(@shapes, assigns.name)))

    ~H"""
    <svg
      class={["hakushi-icon", @class]}
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >{@body}</svg>
    """
  end
end
