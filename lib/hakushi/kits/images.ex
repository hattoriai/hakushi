if Code.ensure_loaded?(Storehouse) do
  defmodule Hakushi.Kits.Images do
    @moduledoc """
    The kit of images on the paper: for a moodboard, a screenshot to mark
    up, references beside a plan.

        <.canvas id="board" graph={@graph} kits={[Hakushi.Kits.Images]} on_change={&save/2} />

    People drop image files on the paper, paste them (or paste an image's
    address, from the hosts the app allows), or pick them with the kit's
    tool (I). Each is a node where it lands, at its own aspect ratio, sized
    to fit the view. While a file uploads, the canvas shows a placeholder
    with its progress (to the others too, on a shared canvas); the node is
    made only once the server has the file and has checked it
    (`Hakushi.Images`).

    An image resizes from its corners and sides with its aspect ratio kept
    (Shift frees it), is cropped in place (the panel's Crop, then Enter),
    takes a caption on a double click, and alt text from the panel. Its
    edges, groups, copy and paste and export are those of any node.

    ## The node

    A node of type `"image"`, whose data is the stored file and how it is
    shown:

        %{
          "url" => "/uploads/2026/10/…-board.png",
          "key" => "2026/10/…-board.png",   # in the store (Storehouse)
          "thumb" => nil,                     # a smaller copy's URL, for small zooms
          "name" => "board.png",
          "pixels" => [1600, 1000],           # the file's width and height
          "crop" => [0, 0, 1, 1],             # x, y, width, height: fractions of the file
          "alt" => "The palette of the spring campaign",
          "caption" => "Spring"
        }

    ## The files

    The files go to the app's store with
    [Storehouse](https://hexdocs.pm/storehouse): the local disk, S3, or a
    store of the app's (`config :storehouse, adapter: ...`). It is an
    optional dependency of Hakushi: the kit is there when the app has
    `{:storehouse, "~> 0.2"}` in its deps. The canvas takes the files with
    a LiveView upload of its own: the canvas must not be in a form of the
    app's. The limits are the kit's config:

        config :hakushi, Hakushi.Kits.Images,
          max_file_size: 10_000_000,     # bytes, the default
          max_entries: 10,               # files at once, the default
          max_pixels: 50_000_000,        # width × height, the default
          fetch: ["images.example.com", "*.cdn.example.com"],
          thumbnail: &MyApp.Images.thumbnail/2,
          files: &MyApp.Images.path/1

      * `:fetch` - the hosts whose images people paste by their address,
        and agents add by theirs: the server downloads them
        (`Hakushi.Images.fetch/2`) and stores them as uploads. None by
        default.
      * `:thumbnail` - a function of the stored image and its file that
        gives the URL of a smaller copy, which the canvas shows when it is
        zoomed out (see `Hakushi.Images.store/2`).
      * `:files` - a function of a name an agent gives (`add_image`'s
        `file`) that gives `{:ok, path}` of one of the app's files, or
        `:error`.
      * `:adapter` - the store, for this kit only. The default is
        `Storehouse.adapter/0`.
    """

    use Hakushi.Kit

    alias Hakushi.Images

    @kind "image"
    # A new image is no wider than this, unless the person sized it.
    @default_width 480
    @min 16
    @caption_max 500
    @alt_max 1_000

    @doc "The kit's config, with its defaults."
    @spec config() :: keyword()
    def config do
      Keyword.merge(
        [max_file_size: 10_000_000, max_entries: 10, max_pixels: 50_000_000, fetch: []],
        Application.get_env(:hakushi, __MODULE__, [])
      )
    end

    @impl true
    def name, do: "images"

    @impl true
    def title(messages), do: messages["kitImages"]

    @impl true
    def icon, do: "image"

    @impl true
    def types, do: [@kind]

    # Images come from files: there is nothing to drop from the kit's bar.
    @impl true
    def elements(_messages), do: []

    @impl true
    def new_node(_item, _at, _messages), do: nil

    @impl true
    def resizable?(@kind), do: true
    def resizable?(_type), do: false

    @impl true
    def tools(messages),
      do: [%{tool: "image", mode: "pick", label: messages["imageAdd"], icon: "image", key: "i"}]

    @impl true
    def styles(messages) do
      [
        %{
          key: "alt",
          label: messages["imageAlt"],
          kind: "text",
          placeholder: messages["imageAltHint"],
          options: []
        },
        %{key: "crop", label: messages["imageCrop"], kind: "action", icon: "crop", options: []}
      ]
    end

    @impl true
    def upload do
      config = config()

      [
        accept: Images.extensions(),
        max_file_size: config[:max_file_size],
        max_entries: config[:max_entries]
      ]
    end

    @impl true
    def uploaded(path, %{name: name}, box, _messages) do
      config = config()

      with {:ok, image} <- Images.store(path, store_opts(config, name: name)) do
        {:ok, image_node(image, box)}
      end
    end

    @impl true
    def pasted(url, box, _messages) do
      config = config()

      case config[:fetch] do
        [_ | _] = hosts ->
          with {:ok, image} <- Images.fetch(url, store_opts(config, hosts: hosts)) do
            {:ok, image_node(image, box)}
          end

        _none ->
          {:error, :not_allowed}
      end
    end

    @doc """
    Whether the kit takes images from the address `url`: its host is one of
    the config's `:fetch`.
    """
    @spec fetchable?(String.t()) :: boolean()
    def fetchable?(url), do: Images.fetchable?(url, config()[:fetch] || [])

    @doc false
    def store_opts(config, opts) do
      config
      |> Keyword.take([:adapter, :thumbnail, :max_pixels, :http])
      |> Keyword.put(:max_bytes, config[:max_file_size])
      |> Keyword.merge(opts)
    end

    @doc """
    An image's node, for a stored image (`Hakushi.Images.store/2`), in a box
    of the canvas: at its `x` and `y`, as wide as it (at most the image's
    own width, and #{@default_width} with no width), and as high as its
    aspect ratio says.

        {:ok, image} = Hakushi.Images.store("priv/seeds/palette.png")
        Hakushi.Kits.Images.image_node(image, [0, 0, 320, 0], alt: "The palette")

    ## Options

      * `:alt` and `:caption` - the image's.
    """
    @spec image_node(Images.image(), [number()] | nil, keyword()) :: map()
    def image_node(image, box, opts \\ []) do
      {x, y, w} =
        case box do
          [x, y, w, _h] when is_number(x) and is_number(y) and is_number(w) and w >= @min ->
            {x, y, w}

          [x, y | _rest] when is_number(x) and is_number(y) ->
            {x, y, min(image.width, @default_width)}

          _none ->
            {0, 0, min(image.width, @default_width)}
        end

      %{
        type: @kind,
        x: round1(x),
        y: round1(y),
        width: round1(w),
        height: round1(w * image.height / image.width),
        data: %{
          "url" => image.url,
          "key" => image.key,
          "thumb" => image.preview,
          "name" => image.name,
          "pixels" => [image.width, image.height],
          "crop" => [0, 0, 1, 1],
          "alt" => text(Keyword.get(opts, :alt), @alt_max),
          "caption" => text(Keyword.get(opts, :caption), @caption_max)
        }
      }
    end

    @impl true
    def edit("text", %{"value" => value}, data) when is_binary(value),
      do: {:ok, Map.put(data, "caption", text(String.trim(value), @caption_max))}

    def edit("style", %{"style" => %{"alt" => alt}}, data) when is_binary(alt),
      do: {:ok, Map.put(data, "alt", text(String.trim(alt), @alt_max))}

    def edit("crop", %{"crop" => crop}, data) do
      case crop(crop) do
        nil -> :error
        crop -> {:ok, Map.put(data, "crop", crop)}
      end
    end

    def edit(_action, _params, _data), do: :error

    # Four fractions of the file, a part of it of some size.
    defp crop([x, y, w, h] = crop)
         when is_number(x) and is_number(y) and is_number(w) and is_number(h) do
      if inside?(x, w) and inside?(y, h),
        do: Enum.map(crop, &(Float.round(&1 * 1.0, 5) |> whole())),
        else: nil
    end

    defp crop(_other), do: nil

    # From `at`, `size` of a side, within it.
    defp inside?(at, size), do: at >= 0 and size > 0.001 and at + size <= 1.0001

    defp whole(n), do: if(n == trunc(n), do: trunc(n), else: n)

    defp text(text, max) when is_binary(text), do: String.slice(text, 0, max)
    defp text(_text, _max), do: ""

    defp round1(n) do
      r = Float.round(n * 1.0, 1)
      if r == trunc(r), do: trunc(r), else: r
    end

    @impl true
    def label(node, messages) do
      word = messages["image"] || "Image"

      case {get(node.data, "alt"), get(node.data, "caption")} do
        {alt, _caption} when is_binary(alt) and alt != "" -> "#{word}: #{alt}"
        {_alt, caption} when is_binary(caption) and caption != "" -> "#{word}: #{caption}"
        _none -> word
      end
    end

    @impl true
    def node(assigns) do
      data = Hakushi.Kit.stringify(assigns.node.data)
      [pw, ph] = pixels(data["pixels"])
      [cx, cy, cw, ch] = crop(data["crop"]) || [0, 0, 1, 1]
      url = if Images.safe_url?(data["url"]), do: data["url"]
      thumb = if Images.safe_url?(data["thumb"]), do: data["thumb"]

      assigns =
        assign(assigns,
          url: url,
          thumb: thumb,
          alt: data["alt"] || "",
          caption: data["caption"] || "",
          aspect: pw * cw / (ph * ch),
          crop: [cx, cy, cw, ch],
          place:
            "width: #{pct(1 / cw)}; height: #{pct(1 / ch)}; " <>
              "left: #{pct(-cx / cw)}; top: #{pct(-cy / ch)};"
        )

      ~H"""
      <figure
        class="hakushi-image"
        data-hakushi-aspect={@aspect}
        data-hakushi-crop={JSON.encode!(@crop)}
        data-hakushi-style={JSON.encode!(%{alt: @alt, crop: @crop})}
      >
        <div class="hakushi-image-frame">
          <img
            :if={@url}
            src={@url}
            data-src={@url}
            data-thumb={@thumb}
            alt={@alt}
            style={@place}
            loading="lazy"
            decoding="async"
            draggable="false"
          />
        </div>
        <figcaption
          class="hakushi-image-caption"
          data-hakushi-text={@caption}
          data-hakushi-text-own
          data-hakushi-text-label={@messages["imageCaption"]}
          data-empty={@caption == "" && "true"}
        >{@caption}</figcaption>
        <.handle side={:top} />
        <.handle side={:right} />
        <.handle side={:bottom} />
        <.handle side={:left} />
      </figure>
      """
    end

    defp pixels([w, h]) when is_integer(w) and is_integer(h) and w > 0 and h > 0, do: [w, h]
    defp pixels(_other), do: [4, 3]

    defp pct(n), do: "#{Float.round(n * 100.0, 4)}%"
  end
end
