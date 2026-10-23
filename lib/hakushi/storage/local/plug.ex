defmodule Hakushi.Storage.Local.Plug do
  @moduledoc """
  Serves the files of `Hakushi.Storage.Local`, read only.

  In the endpoint, before the router:

      plug Hakushi.Storage.Local.Plug

  The plug answers `GET` and `HEAD` requests under the `:at` path (by
  default the configured `:url_prefix` of `Hakushi.Storage.Local`), and
  passes every other request on. In a router, `forward` strips the path, so
  give `at: "/"`:

      forward "/uploads/hakushi", Hakushi.Storage.Local.Plug, at: "/"

  ## Options

    * `:at` - the request path of the files. The default is the configured
      `:url_prefix`.
    * `:root` - the directory. The default is the configured `:root`.
    * `:max_age` - the `max-age` of the `Cache-Control` header, in seconds.
      The default is `3600`.

  ## Responses

    * A PNG, JPEG, GIF or WebP image (by its extension, which its key has
      from its checked type) is sent with its type; any other file as
      `application/octet-stream`, with `Content-Disposition: attachment`.
    * `Cache-Control: private, max-age=…`, `X-Content-Type-Options: nosniff`
      and `Content-Security-Policy: default-src 'none'; sandbox`, so a file
      cannot run a script on the app's origin.
    * A path with a segment that is not a valid key segment gives `400`. A
      key with no regular file gives `404`: a directory, a symbolic link,
      and a path through a symbolic link included.
  """

  @behaviour Plug

  import Plug.Conn

  alias Hakushi.{Images, Storage}
  alias Hakushi.Storage.Local

  @impl Plug
  def init(opts), do: Keyword.validate!(opts, [:at, :root, max_age: 3600])

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, opts) when method in ["GET", "HEAD"] do
    at = split(Keyword.get_lazy(opts, :at, &Local.url_prefix/0))

    case strip(conn.path_info, at) do
      nil -> conn
      segments -> serve(conn, segments, opts)
    end
  end

  def call(conn, _opts), do: conn

  defp split(path), do: String.split(path, "/", trim: true)

  defp strip(path_info, []), do: path_info
  defp strip([segment | path_info], [segment | at]), do: strip(path_info, at)
  defp strip(_path_info, _at), do: nil

  defp serve(conn, [], _opts), do: halt_with(conn, 404)

  defp serve(conn, segments, opts) do
    if Enum.all?(segments, &Storage.valid_segment?/1) do
      root = opts |> Keyword.get_lazy(:root, &Local.root/0) |> Path.expand()

      case regular_file(root, segments) do
        {:ok, path} -> send_image(conn, path, opts)
        :error -> halt_with(conn, 404)
      end
    else
      halt_with(conn, 400)
    end
  end

  # Each directory under the root must be a real directory and the last
  # segment a regular file: a symbolic link at any level gives :error.
  defp regular_file(root, segments) do
    {directories, [file]} = Enum.split(segments, -1)

    directory =
      Enum.reduce_while(directories, root, fn segment, parent ->
        path = Path.join(parent, segment)

        case File.lstat(path) do
          {:ok, %File.Stat{type: :directory}} -> {:cont, path}
          _other -> {:halt, nil}
        end
      end)

    with directory when is_binary(directory) <- directory,
         path = Path.join(directory, file),
         {:ok, %File.Stat{type: :regular}} <- File.lstat(path) do
      {:ok, path}
    else
      _other -> :error
    end
  end

  defp send_image(conn, path, opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, max-age=#{opts[:max_age]}")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")

    conn =
      case Images.content_type(Path.extname(path)) do
        nil ->
          conn
          |> put_resp_content_type("application/octet-stream", nil)
          |> put_resp_header("content-disposition", "attachment")

        type ->
          put_resp_content_type(conn, type, nil)
      end

    conn |> send_file(200, path) |> halt()
  end

  defp halt_with(conn, status), do: conn |> send_resp(status, "") |> halt()
end
