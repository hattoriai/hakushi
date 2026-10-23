if Code.ensure_loaded?(Storehouse) do
  defmodule Hakushi.Images do
    @moduledoc """
    The images of a canvas (`Hakushi.Kits.Images`), checked on the server
    before they become nodes, and kept in the app's store with
    [Storehouse](https://hexdocs.pm/storehouse).

    The browser's content type is a claim. Storehouse reads the bytes of
    the file (`Storehouse.Check`): a PNG, JPEG, GIF or WebP image, from its
    signature, with its width and height from its header (a JPEG's turned
    as its EXIF orientation says, as browsers draw it). Any other file is
    refused, an SVG too (it may hold a script), and an image whose header
    has no size.

    `store/2` checks a file and stores it under a new key, in the store of
    `config :storehouse, adapter: ...` (the local disk, S3, or one of the
    app's); `fetch/2` downloads an image from an address of the hosts an
    app allows, then stores it, so an image pasted by its address, or added
    by an agent, is the app's own file as an upload is.
    """

    @types %{
      "image/png" => ".png",
      "image/jpeg" => ".jpg",
      "image/gif" => ".gif",
      "image/webp" => ".webp"
    }
    @by_extension Map.new(@types, fn {type, ext} -> {ext, type} end)
                  |> Map.put(".jpeg", "image/jpeg")
    @default_max_bytes 10_000_000
    # Width × height: an image larger than this is refused, which a browser
    # would struggle to draw.
    @default_max_pixels 50_000_000

    @typedoc """
    A stored image: a `Storehouse.File`, with its `key` and `url` in the
    store, the client's `name`, its checked `content_type`, `bytes`,
    `width`, `height` and `checksum`, and the URL of a smaller copy
    (`preview`), or `nil`.
    """
    @type image :: Storehouse.File.t()

    @doc "The content types of the images a canvas takes."
    @spec types() :: [String.t()]
    def types, do: Map.keys(@types)

    @doc "The file extensions of the images a canvas takes, as an upload's `accept`."
    @spec extensions() :: [String.t()]
    def extensions, do: ~w(.png .jpg .jpeg .gif .webp)

    @doc """
    The content type of an image's file extension (`".png"`), or `nil` for
    another.
    """
    @spec content_type(String.t()) :: String.t() | nil
    def content_type(extension),
      do: Map.get(@by_extension, String.downcase(extension))

    @doc """
    Checks the image at `path` and stores it under a new key, with
    `Storehouse.store/2`. The file at `path` is left where it is.

    A file that is not an image a canvas takes gives
    `{:error, :not_an_image}`; one over a limit, `{:error, :too_large}`.

    ## Options

      * `:name` - the file's name, for its key and its node. The default is
        the base name of `path`.
      * `:adapter` - the store. The default is `Storehouse.adapter/0`.
      * `:thumbnail` - a function of the stored image (a `Storehouse.File`)
        and `path` that gives the URL of a smaller copy, or `nil`: the app
        makes and stores it (with `image` or `vix`, say). The canvas shows it
        when it is zoomed out. An exception, or a result that is not a URL,
        gives none.
      * `:max_bytes` - the largest file. The default is 10 MB.
      * `:max_pixels` - the most pixels (width × height). The default is
        50 million.
    """
    @spec store(Path.t(), keyword()) :: {:ok, image()} | {:error, term()}
    def store(path, opts \\ []) when is_binary(path) do
      path |> Storehouse.store(storehouse_opts(opts)) |> image(opts)
    end

    @doc """
    Downloads the image at `url`, from a host of `:hosts`, then checks and
    stores it as `store/2` does (`Storehouse.fetch/2`).

    Only `https` addresses (and `http`, with `http: true`) of the hosts the
    app allows are fetched, and a redirect only to one of them: the server
    never fetches an address a person or an agent chose freely, which could
    be one of the app's own network. A host is a name (`"images.example.com"`)
    or a name with a leading `*.` for its subdomains (`"*.example.com"`).

    ## Options

      * `:hosts` - the hosts it fetches from (required).
      * `:http` - whether `http` addresses are fetched. The default is
        `false`.
      * `:timeout` - in milliseconds, for the whole download. The default
        is 10 seconds.
      * the options of `store/2`.
    """
    @spec fetch(String.t(), keyword()) :: {:ok, image()} | {:error, term()}
    def fetch(url, opts) when is_binary(url) do
      fetch_opts = Keyword.take(opts, [:hosts, :http, :timeout])
      url |> Storehouse.fetch(fetch_opts ++ storehouse_opts(opts)) |> image(opts)
    end

    @doc """
    Whether `url` is an address that `fetch/2` takes with `hosts` (`https`
    only).

        iex> Hakushi.Images.fetchable?("https://images.example.com/a.png", ["*.example.com"])
        true

        iex> Hakushi.Images.fetchable?("https://example.org/a.png", ["*.example.com"])
        false

    """
    @spec fetchable?(String.t(), [String.t()]) :: boolean()
    defdelegate fetchable?(url, hosts), to: Storehouse

    @doc """
    Whether `url` is an address an image node may show: `http` or `https`,
    or a path of the app (`/uploads/…`).
    """
    @spec safe_url?(term()) :: boolean()
    defdelegate safe_url?(url), to: Storehouse

    defp storehouse_opts(opts) do
      [
        accept: types(),
        max_bytes: Keyword.get(opts, :max_bytes) || @default_max_bytes,
        max_pixels: Keyword.get(opts, :max_pixels) || @default_max_pixels,
        preview: Keyword.get(opts, :thumbnail)
      ] ++ Keyword.take(opts, [:name, :adapter])
    end

    # An image a canvas draws has a size: a file whose header gives none is
    # deleted again.
    defp image({:ok, %Storehouse.File{width: w, height: h} = file}, _opts)
         when is_integer(w) and is_integer(h),
         do: {:ok, file}

    defp image({:ok, %Storehouse.File{key: key}}, opts) do
      _result = Storehouse.delete(key, Keyword.take(opts, [:adapter]))
      {:error, :not_an_image}
    end

    defp image({:error, :not_accepted}, _opts), do: {:error, :not_an_image}
    defp image({:error, _reason} = error, _opts), do: error
  end
end
