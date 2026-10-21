defmodule Hakushi.Messages do
  @moduledoc """
  The words of the canvas: the labels of its controls, the reasons it
  gives when it refuses a change, and the announcements for screen
  readers.

  The words in your nodes are yours (translate them as the rest of your
  app, with Gettext). The canvas's own words are here, in English,
  Portuguese, Spanish, French, German and Japanese; a locale with a region (`pt-BR`, `en-GB`) takes the words of
  its language, and another language gets English.

  Give the palette other words with `messages`, a map from the keys of
  `keys/0` to the new words, for example your own Gettext translations:

      <Hakushi.Components.canvas id="board" graph={@graph} messages={%{"fit" => gettext("Show all")}} />

  Or set them for every canvas in the config:

      config :hakushi, messages: %{"fr" => %{"fit" => "Tout voir"}}

  A word may have placeholders in braces (`{n}`, `{name}`), which the
  canvas fills. The keys that end in `One` and `Other` are the plural
  forms of a count, picked with the plural rules of the locale.
  """

  alias Hakushi.Messages.Translations

  @doc """
  Returns the keys of the messages.

  ## Examples

      iex> "fit" in Hakushi.Messages.keys()
      true

  """
  @spec keys() :: [String.t()]
  def keys, do: Map.keys(Translations.english())

  @doc """
  Returns the languages with built-in words.

  ## Examples

      iex> Hakushi.Messages.languages()
      ["de", "en", "es", "fr", "ja", "pt"]

  """
  @spec languages() :: [String.t()]
  def languages, do: Translations.all() |> Map.keys() |> Enum.sort()

  @doc """
  The words for a locale: the built-in words of its language, then the
  words of the config for the locale and for its language, then
  `overrides`. Every key has a value (English when a language lacks one).

  Raises `ArgumentError` for an override with an unknown key, so that a
  typo shows.

  ## Examples

      iex> Hakushi.Messages.for_locale("pt-PT")["fit"]
      "Ver tudo"
      iex> Hakushi.Messages.for_locale("sv")["fit"]
      "Fit to screen"
      iex> Hakushi.Messages.for_locale("en", %{"fit" => "Show all"})["fit"]
      "Show all"

  """
  @spec for_locale(String.t(), map()) :: %{String.t() => String.t()}
  def for_locale(locale, overrides \\ %{}) when is_binary(locale) do
    language = language(locale)
    config = Application.get_env(:hakushi, :messages, %{})

    Translations.english()
    |> Map.merge(Map.get(Translations.all(), language, %{}))
    |> Map.merge(stringify(Map.get(config, language, %{})))
    |> Map.merge(stringify(Map.get(config, locale, %{})))
    |> Map.merge(check!(stringify(overrides || %{})))
  end

  @doc """
  The language of a locale: `"pt"` for `"pt-BR"`, `"zh"` for `"zh_Hant"`.

  ## Examples

      iex> Hakushi.Messages.language("pt-BR")
      "pt"

  """
  @spec language(String.t()) :: String.t()
  def language(locale) do
    locale |> String.split(["-", "_"], parts: 2) |> hd() |> String.downcase()
  end

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)

  defp check!(overrides) do
    english = Translations.english()

    case Enum.reject(Map.keys(overrides), &Map.has_key?(english, &1)) do
      [] ->
        overrides

      unknown ->
        raise ArgumentError,
              "Hakushi.Messages: unknown message keys #{inspect(unknown)}; see Hakushi.Messages.keys/0"
    end
  end

  @doc """
  The words for a reason the canvas refused a change: a reason of
  `Hakushi.Graph.apply/2` or `Hakushi.Rules.check/3` (an atom), or the
  app's own words (a string) as they are.

  ## Examples

      iex> Hakushi.Messages.reason(Hakushi.Messages.for_locale("en"), :loop)
      "A node cannot connect to itself."
      iex> Hakushi.Messages.reason(%{}, "Only one owner.")
      "Only one owner."

  """
  @spec reason(map(), atom() | String.t()) :: String.t()
  def reason(_messages, reason) when is_binary(reason), do: reason

  def reason(messages, reason) when is_atom(reason) do
    key = "refused" <> Macro.camelize(Atom.to_string(reason))
    Map.get(messages, key) || Map.get(messages, "refused") || Translations.english()["refused"]
  end
end
