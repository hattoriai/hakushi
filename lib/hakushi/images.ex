defmodule Hakushi.Images do
  @moduledoc """
  The images of a canvas (`Hakushi.Kits.Images`), checked on the server
  before they become nodes.

  The browser's content type is a claim. `describe/1` reads the bytes of
  the file: a PNG, JPEG, GIF or WebP image, from its signature, with its
  width and height from its header (a JPEG's turned as its EXIF
  orientation says, as browsers draw it). Any other file is refused, an
  SVG too (it may hold a script), and an image whose header has no size.

  `store/2` checks a file and stores it through the storage adapter
  (`Hakushi.Storage`), under a new key; `fetch/2` downloads an image from
  an address of the hosts an app allows, then stores it, so an image
  pasted by its address, or added by an agent, is the app's own file as
  an upload is.
  """

  import Bitwise

  require Logger

  alias Hakushi.Storage

  # The start of a file that `describe/1` reads: a JPEG's EXIF (at most
  # 64 KB) comes before its size.
  @head 262_144
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
  @max_redirects 3

  @typedoc "What `describe/1` finds."
  @type description :: %{
          content_type: String.t(),
          bytes: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer()
        }

  @typedoc """
  A stored image: its `key` and `url` in the store, the client's `name`,
  its checked `content_type`, `bytes`, `width` and `height`, and the URL
  of a smaller copy (`thumb`), or `nil`.
  """
  @type image :: %{
          key: String.t(),
          url: String.t(),
          name: String.t(),
          content_type: String.t(),
          bytes: non_neg_integer(),
          width: pos_integer(),
          height: pos_integer(),
          thumb: String.t() | nil
        }

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
  Reads the file at `path`: `{:ok, description}` for an image, else
  `{:error, :not_an_image}` (or the error reading it).

  ## Options

    * `:max_bytes` - the largest file. The default is 10 MB.
    * `:max_pixels` - the most pixels (width × height). The default is
      50 million.
  """
  @spec describe(Path.t(), keyword()) :: {:ok, description()} | {:error, term()}
  def describe(path, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    max_pixels = Keyword.get(opts, :max_pixels, @default_max_pixels)

    with {:ok, %File.Stat{size: bytes}} <- File.stat(path),
         :ok <- if(bytes <= max_bytes, do: :ok, else: {:error, :too_large}),
         {:ok, head} <- read_head(path),
         {type, w, h} when is_integer(w) and is_integer(h) <- image(head),
         :ok <- if(w * h <= max_pixels, do: :ok, else: {:error, :too_large}) do
      {:ok, %{content_type: type, bytes: bytes, width: w, height: h}}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :not_an_image}
    end
  end

  @doc """
  Checks the image at `path` and stores it under a new key, through the
  storage adapter. The file at `path` is left where it is.

  ## Options

    * `:name` - the file's name, for its key and its node. The default is
      the base name of `path`.
    * `:storage` - the storage adapter. The default is
      `Hakushi.Storage.adapter/0`.
    * `:thumbnail` - a function of the stored image and `path` that gives
      the URL of a smaller copy, or `nil`: the app makes and stores it
      (with `image` or `vix`, say). The canvas shows it when it is zoomed
      out. An exception, or a result that is not a URL, gives none.
    * `:max_bytes`, `:max_pixels` - as for `describe/2`.
  """
  @spec store(Path.t(), keyword()) :: {:ok, image()} | {:error, term()}
  def store(path, opts \\ []) when is_binary(path) do
    name = clean_name(Keyword.get_lazy(opts, :name, fn -> Path.basename(path) end))
    storage = Keyword.get_lazy(opts, :storage, &Storage.adapter/0)

    with {:ok, description} <- describe(path, opts),
         key = Storage.key(name, @types[description.content_type]),
         meta = %{name: name, content_type: description.content_type, bytes: description.bytes},
         {:ok, url} <- put(storage, key, path, meta) do
      image = Map.merge(description, %{key: key, url: url, name: name, thumb: nil})
      {:ok, %{image | thumb: thumbnail(Keyword.get(opts, :thumbnail), image, path)}}
    end
  end

  defp put(storage, key, path, meta) do
    case storage.put(key, path, meta) do
      {:ok, url} when is_binary(url) ->
        if safe_url?(url),
          do: {:ok, url},
          else: discard(storage, key, {:error, {:unsafe_url, url}})

      {:error, reason} ->
        {:error, reason}

      other ->
        discard(storage, key, {:error, {:invalid_storage_result, other}})
    end
  end

  defp discard(storage, key, error) do
    _result = storage.delete(key)
    error
  end

  defp thumbnail(nil, _image, _path), do: nil

  defp thumbnail(fun, image, path) do
    case fun.(image, path) do
      url when is_binary(url) ->
        if safe_url?(url), do: url, else: no_thumbnail(image, {:unsafe_url, url})

      nil ->
        nil

      other ->
        no_thumbnail(image, {:invalid_thumbnail, other})
    end
  rescue
    exception -> no_thumbnail(image, exception)
  end

  defp no_thumbnail(image, reason) do
    Logger.warning(
      "Hakushi: no thumbnail for the image #{inspect(image.name)}: #{inspect(reason)}"
    )

    nil
  end

  @doc """
  Downloads the image at `url`, from a host of `:hosts`, then checks and
  stores it as `store/2` does.

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
    hosts = Keyword.fetch!(opts, :hosts)
    schemes = if Keyword.get(opts, :http, false), do: ["https", "http"], else: ["https"]
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)

    with {:ok, uri} <- allowed(url, hosts, schemes),
         {:ok, body} <- download(uri, hosts, schemes, max_bytes, opts, @max_redirects) do
      path = Path.join(System.tmp_dir!(), "hakushi-fetch-#{System.unique_integer([:positive])}")

      try do
        File.write!(path, body)
        name = uri.path |> to_string() |> Path.basename() |> URI.decode()
        store(path, Keyword.put_new(opts, :name, if(name == "", do: "image", else: name)))
      after
        File.rm(path)
      end
    end
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
  def fetchable?(url, hosts), do: match?({:ok, _uri}, allowed(url, hosts, ["https"]))

  defp allowed(url, hosts, schemes) do
    with %URI{scheme: scheme, host: host} = uri when is_binary(host) <- URI.parse(url),
         true <- scheme in schemes,
         true <- host_allowed?(String.downcase(host), hosts) do
      {:ok, uri}
    else
      _other -> {:error, :not_allowed}
    end
  end

  defp host_allowed?(host, hosts) do
    Enum.any?(hosts, fn
      "*." <> domain -> String.ends_with?(host, "." <> String.downcase(domain))
      allowed -> host == String.downcase(allowed)
    end)
  end

  defp download(_uri, _hosts, _schemes, _max, _opts, -1), do: {:error, :too_many_redirects}

  defp download(uri, hosts, schemes, max_bytes, opts, redirects) do
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl])
    timeout = Keyword.get(opts, :timeout, 10_000)
    url = String.to_charlist(URI.to_string(uri))

    http_opts = [
      timeout: timeout,
      connect_timeout: timeout,
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:get, {url, [{~c"accept", ~c"image/*"}]}, http_opts, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _headers, body}} when status in 200..299 ->
        if byte_size(body) <= max_bytes, do: {:ok, body}, else: {:error, :too_large}

      {:ok, {{_version, status, _reason}, headers, _body}}
      when status in [301, 302, 303, 307, 308] ->
        with {_name, location} <- List.keyfind(headers, ~c"location", 0),
             next = URI.merge(uri, to_string(location)),
             {:ok, next} <- allowed(URI.to_string(next), hosts, schemes) do
          download(next, hosts, schemes, max_bytes, opts, redirects - 1)
        else
          nil -> {:error, :not_found}
          error -> error
        end

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Whether `url` is an address an image node may show: `http` or `https`,
  or a path of the app (`/uploads/…`).
  """
  @spec safe_url?(term()) :: boolean()
  def safe_url?("/" <> rest = url) when byte_size(url) <= 2_048,
    do: not String.starts_with?(rest, ["/", "\\"]) and not String.contains?(url, ["\"", "<", ">"])

  def safe_url?(url) when is_binary(url) and byte_size(url) <= 2_048 do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != "" and not String.contains?(url, ["\"", "<", ">", " "])

      _other ->
        false
    end
  end

  def safe_url?(_url), do: false

  @doc false
  # A file's name to show: no control or format characters, at most 200
  # characters.
  def clean_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[\p{Cc}\p{Cf}]/u, "")
    |> String.trim()
    |> String.slice(0, 200)
    |> case do
      "" -> "image"
      name -> name
    end
  end

  def clean_name(_name), do: "image"

  defp read_head(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, @head)) do
      {:ok, :eof} -> {:ok, ""}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, head} -> {:ok, head}
      {:error, reason} -> {:error, reason}
    end
  end

  # PNG: the IHDR chunk comes first.
  defp image(<<0x89, "PNG\r\n", 0x1A, "\n", _length::32, "IHDR", w::32, h::32, _rest::binary>>),
    do: {"image/png", dimension(w), dimension(h)}

  defp image(<<"GIF8", v, "a", w::little-16, h::little-16, _rest::binary>>) when v in [?7, ?9],
    do: {"image/gif", dimension(w), dimension(h)}

  defp image(<<"RIFF", _size::little-32, "WEBP", chunk::binary>>) do
    {width, height} = webp(chunk)
    {"image/webp", width, height}
  end

  defp image(<<0xFF, 0xD8, 0xFF, rest::binary>>) do
    {width, height} = jpeg(<<0xFF, rest::binary>>, 1)
    {"image/jpeg", width, height}
  end

  defp image(_head), do: nil

  defp webp(
         <<"VP8 ", _size::little-32, _frame::binary-size(3), 0x9D, 0x01, 0x2A, w::little-16,
           h::little-16, _rest::binary>>
       ) do
    {dimension(w &&& 0x3FFF), dimension(h &&& 0x3FFF)}
  end

  defp webp(<<"VP8L", _size::little-32, 0x2F, bits::little-32, _rest::binary>>) do
    {dimension((bits &&& 0x3FFF) + 1), dimension((bits >>> 14 &&& 0x3FFF) + 1)}
  end

  defp webp(<<"VP8X", _size::little-32, _flags::32, w::little-24, h::little-24, _rest::binary>>),
    do: {dimension(w + 1), dimension(h + 1)}

  defp webp(_chunk), do: {nil, nil}

  # JPEG: walk the markers up to a start-of-frame marker, reading the EXIF
  # orientation on the way: 5 to 8 turn the image a quarter, and browsers
  # draw it so.
  defp jpeg(<<0xFF, marker, _length::16, _precision, h::16, w::16, _rest::binary>>, orientation)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC] do
    if orientation in 5..8,
      do: {dimension(h), dimension(w)},
      else: {dimension(w), dimension(h)}
  end

  defp jpeg(<<0xFF, 0xFF, rest::binary>>, orientation),
    do: jpeg(<<0xFF, rest::binary>>, orientation)

  defp jpeg(<<0xFF, marker, rest::binary>>, orientation)
       when marker in 0xD0..0xD9 or marker == 0x01,
       do: jpeg(rest, orientation)

  defp jpeg(<<0xFF, marker, length::16, rest::binary>>, orientation) when length >= 2 do
    skip = length - 2

    case rest do
      <<segment::binary-size(^skip), next::binary>> ->
        orientation =
          if marker == 0xE1, do: exif_orientation(segment) || orientation, else: orientation

        jpeg(next, orientation)

      _short ->
        {nil, nil}
    end
  end

  defp jpeg(_other, _orientation), do: {nil, nil}

  # The Orientation tag (0x0112) of the first IFD of an APP1 "Exif" segment.
  defp exif_orientation(<<"Exif", 0, 0, tiff::binary>>) do
    case tiff do
      <<"II", 42::little-16, ifd::little-32, _rest::binary>> ->
        ifd_orientation(tiff, ifd, :little)

      <<"MM", 42::big-16, ifd::big-32, _rest::binary>> ->
        ifd_orientation(tiff, ifd, :big)

      _other ->
        nil
    end
  end

  defp exif_orientation(_segment), do: nil

  defp ifd_orientation(tiff, offset, endian) do
    with <<_skip::binary-size(^offset), count::binary-2, entries::binary>> <- tiff,
         count = uint(count, endian),
         true <- byte_size(entries) >= count * 12 do
      Enum.find_value(
        0..(count - 1)//1,
        &orientation_entry(binary_part(entries, &1 * 12, 12), endian)
      )
    else
      _other -> nil
    end
  end

  defp orientation_entry(
         <<tag::binary-2, _type::binary-2, _count::binary-4, value::binary-2, _pad::binary-2>>,
         endian
       ) do
    if uint(tag, endian) == 0x0112, do: uint(value, endian)
  end

  defp uint(<<n::little-16>>, :little), do: n
  defp uint(<<n::big-16>>, :big), do: n

  defp dimension(value) when is_integer(value) and value > 0, do: value
  defp dimension(_value), do: nil
end
