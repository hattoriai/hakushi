defmodule Hakushi.Storage do
  @moduledoc """
  The behaviour of a file store for the images of a canvas
  (`Hakushi.Kits.Images`).

  It is Kotoba's (`Kotoba.Storage`): the same three callbacks, the same
  keys, the same URLs. An app that has a store for Kotoba names it here as
  it is, and the images of its canvases go where the attachments of its
  documents go:

      config :hakushi, storage: MyApp.KotobaStorage

  With no `:storage` of Hakushi's, the canvas takes Kotoba's
  (`config :kotoba, storage: ...`), and else `Hakushi.Storage.Local`.

  ## Keys

  A key is a relative path with segments of ASCII letters, digits, `.`, `-`
  and `_`, separated by `/`. A segment is never `.` or `..`. `key/2` makes
  a new key in the form `yyyy/mm/<uuid>-<safe name><extension>`, whose
  extension comes from the type the bytes of the file prove
  (`Hakushi.Images.describe/1`), never from the client's file name. An
  adapter refuses a key that `valid_key?/1` refuses.

  ## Serving the files

  An uploaded file is content from a user. Serve it with
  `X-Content-Type-Options: nosniff` and its checked content type, as
  `Hakushi.Storage.Local.Plug` does. To draw the images in a PNG or an SVG
  of the canvas (its export), the browser reads them: serve them from the
  app's origin, or with CORS headers that allow it.

  ## Another store

  A module with the three callbacks, named in the config. For example,
  with `ExAws.S3`:

      defmodule MyApp.Storage do
        @behaviour Hakushi.Storage

        @bucket "my-app-uploads"

        @impl true
        def put(key, path, meta) do
          path
          |> ExAws.S3.Upload.stream_file()
          |> ExAws.S3.upload(@bucket, key, content_type: meta.content_type)
          |> ExAws.request()
          |> case do
            {:ok, _response} -> {:ok, url(key)}
            {:error, reason} -> {:error, reason}
          end
        end

        @impl true
        def url(key), do: "https://\#{@bucket}.s3.amazonaws.com/" <> key

        @impl true
        def delete(key) do
          case ExAws.request(ExAws.S3.delete_object(@bucket, key)) do
            {:ok, _response} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end

  The URL goes into the canvas's graph, so it must stay valid: a public or
  CDN URL, or a path in the app (`"/files/" <> key`) whose controller
  checks access and redirects to a short-lived signed URL.
  """

  @typedoc "A storage key, for example `\"2026/10/0b6…-moodboard.png\"`."
  @type key :: String.t()

  @typedoc """
  What Hakushi knows about the file: `:name` (the client's file name, for
  display only), `:content_type` (checked on the server) and `:bytes`.
  """
  @type meta :: %{
          optional(:name) => String.t(),
          optional(:content_type) => String.t(),
          optional(:bytes) => non_neg_integer()
        }

  @doc """
  Stores the file at `path` under `key`, and returns its URL.

  The file at `path` is a temporary file: the adapter copies it, and must
  not keep a reference to it.
  """
  @callback put(key(), path :: Path.t(), meta()) :: {:ok, url :: String.t()} | {:error, term()}

  @doc "Returns the URL of the file with `key`."
  @callback url(key()) :: String.t()

  @doc "Deletes the file with `key`. A key with no file gives `:ok`."
  @callback delete(key()) :: :ok | {:error, term()}

  @max_name 100
  @max_key 255
  @segment ~r/\A[A-Za-z0-9._\-]+\z/

  @doc """
  Returns the store of the images: `config :hakushi, storage: ...`, else
  Kotoba's (`config :kotoba, storage: ...`), else `Hakushi.Storage.Local`.
  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:hakushi, :storage) || Application.get_env(:kotoba, :storage) ||
      Hakushi.Storage.Local
  end

  @doc """
  Returns a new key for a file: `yyyy/mm/<uuid>-<safe name><extension>`,
  with the year and month of now (UTC), a random UUID, and `extension`
  (the checked type's, with its dot).

  ## Examples

      iex> key = Hakushi.Storage.key("My board (1).png", ".png")
      iex> [_year, _month, file] = String.split(key, "/")
      iex> String.slice(file, 37..-1//1)
      "My_board_1_.png"

  """
  @spec key(String.t(), String.t()) :: key()
  def key(name, extension) when is_binary(name) and is_binary(extension) do
    now = DateTime.utc_now()
    year = now.year |> Integer.to_string() |> String.pad_leading(4, "0")
    month = now.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{year}/#{month}/#{uuid()}-#{safe_name(name, extension)}"
  end

  @doc """
  Returns a safe file name for a key: the client's name without its
  extension, with only ASCII letters, digits, `.`, `-` and `_`, then
  `extension`. At most #{@max_name} characters.

  ## Examples

      iex> Hakushi.Storage.safe_name("photo.html", ".png")
      "photo.png"

      iex> Hakushi.Storage.safe_name("../../etc/passwd", ".jpg")
      "._._etc_passwd.jpg"

      iex> Hakushi.Storage.safe_name("", ".gif")
      "file.gif"

  """
  @spec safe_name(String.t(), String.t()) :: String.t()
  def safe_name(name, extension) when is_binary(name) and is_binary(extension) do
    base =
      name
      |> Path.rootname()
      |> String.replace(~r/[^A-Za-z0-9._\-]+/, "_")
      |> String.replace(~r/\.{2,}/, ".")
      |> String.trim_trailing(".")

    base = if base in ["", "_"], do: "file", else: base
    binary_part(base, 0, min(byte_size(base), @max_name - byte_size(extension))) <> extension
  end

  @doc """
  Returns `true` when `key` is a valid storage key.

  ## Examples

      iex> Hakushi.Storage.valid_key?("2026/10/a-board.png")
      true

      iex> Hakushi.Storage.valid_key?("2026/../../etc/passwd")
      false

  """
  @spec valid_key?(term()) :: boolean()
  def valid_key?(key) when is_binary(key) and byte_size(key) in 1..@max_key do
    key |> String.split("/") |> Enum.all?(&valid_segment?/1)
  end

  def valid_key?(_key), do: false

  @doc false
  @spec valid_segment?(String.t()) :: boolean()
  def valid_segment?(segment) when segment in ["", ".", ".."], do: false
  def valid_segment?(segment) when is_binary(segment), do: Regex.match?(@segment, segment)

  defp uuid do
    <<a::48, _version::4, b::12, _variant::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn <<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>> ->
      Enum.join([a, b, c, d, e], "-")
    end)
  end
end
