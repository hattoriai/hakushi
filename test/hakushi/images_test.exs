defmodule Hakushi.ImagesTest do
  # Images (Hakushi.Kits.Images): the files checked and stored (with
  # Storehouse), the kit's nodes, a canvas that takes uploads, and an agent
  # that adds an image.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2]
  import Hakushi.Test

  alias Hakushi.Images
  alias Hakushi.Kits.Images, as: Kit
  alias Issho.Tool.Context
  alias Storehouse.Local
  alias Storehouse.Local.Plug, as: LocalPlug

  doctest Hakushi.Images

  @endpoint HakushiTest.Endpoint
  @fixtures Path.expand("../fixtures/images", __DIR__)

  defp fixture(name), do: Path.join(@fixtures, name)

  setup do
    root = Path.join(System.tmp_dir!(), "hakushi-images-#{System.unique_integer([:positive])}")
    Application.put_env(:storehouse, Local, root: root)

    on_exit(fn ->
      File.rm_rf!(root)
      Application.delete_env(:storehouse, Local)
      Application.delete_env(:hakushi, Kit)
    end)

    %{root: root}
  end

  describe "an image's file" do
    test "is a PNG, a JPEG, a GIF or a WebP, by its bytes, with its size" do
      assert {:ok, %{content_type: "image/png", width: 4, height: 3, bytes: 77}} =
               Images.store(fixture("small.png"))

      assert {:ok, %{content_type: "image/gif", width: 5, height: 7}} =
               Images.store(fixture("small.gif"))

      assert {:ok, %{content_type: "image/webp", width: 6, height: 2}} =
               Images.store(fixture("small.webp"))

      assert {:ok, %{content_type: "image/jpeg", width: 1200, height: 800}} =
               Images.store(fixture("harbour.jpg"))
    end

    test "is turned as its EXIF says, as the browser draws it" do
      # 8 × 6, with the orientation 6: a quarter turn.
      assert {:ok, %{width: 6, height: 8}} = Images.store(fixture("turned.jpg"))
    end

    test "is refused when it is not one: an SVG, a page called .png, too large",
         %{root: root} do
      assert {:error, :not_an_image} = Images.store(fixture("drawing.svg"))
      assert {:error, :not_an_image} = Images.store(fixture("not-an-image.png"))
      assert {:error, :too_large} = Images.store(fixture("harbour.jpg"), max_bytes: 1_000)
      assert {:error, :too_large} = Images.store(fixture("harbour.jpg"), max_pixels: 10_000)
      assert Path.wildcard(Path.join(root, "**/*.*")) == []
    end

    test "is stored under a new key with its checked type's extension", %{root: root} do
      assert {:ok, image} = Images.store(fixture("small.png"), name: "board <1>.html")

      assert %Storehouse.File{content_type: "image/png", width: 4, height: 3} = image
      assert image.name == "board <1>.html"
      assert image.key =~ ~r"\A\d{4}/\d{2}/[0-9a-f-]{36}-board_1_\.png\z"
      assert image.url == "/uploads/" <> image.key
      assert image.checksum == Storehouse.checksum(fixture("small.png"))
      assert File.read!(Path.join(root, image.key)) == File.read!(fixture("small.png"))
      assert image.preview == nil
    end

    test "has a smaller copy when the app makes one, and none when it fails" do
      thumbnail = fn image, path ->
        assert File.exists?(path)
        "/thumbs/" <> image.key
      end

      assert {:ok, %{preview: "/thumbs/" <> _}} =
               Images.store(fixture("small.png"), thumbnail: thumbnail)

      assert {:ok, %{preview: nil}} =
               Images.store(fixture("small.png"), thumbnail: fn _, _ -> raise "no" end)

      assert {:ok, %{preview: nil}} =
               Images.store(fixture("small.png"), thumbnail: fn _, _ -> "javascript:1" end)
    end

    test "is not stored when the store gives an unsafe address", %{root: root} do
      defmodule Unsafe do
        def put(key, path, meta),
          do: with({:ok, _} <- Local.put(key, path, meta), do: {:ok, "javascript:alert(1)"})

        def delete(key), do: Local.delete(key)
        def url(key), do: key
      end

      assert {:error, {:unsafe_url, _}} = Images.store(fixture("small.png"), adapter: Unsafe)
      assert Path.wildcard(Path.join(root, "**/*.png")) == []
    end

    test "is fetched only from the hosts the app allows" do
      assert {:error, :not_allowed} =
               Images.fetch("https://example.org/a.png", hosts: ["example.com"])

      assert {:error, :not_allowed} =
               Images.fetch("http://example.com/a.png", hosts: ["example.com"])

      assert {:error, :not_allowed} = Images.fetch("file:///etc/passwd", hosts: ["example.com"])
      assert Images.fetchable?("https://cdn.example.com/a.png", ["*.example.com"])
      refute Images.fetchable?("https://example.com.evil.org/a.png", ["*.example.com"])
    end

    test "shows only from an address of the web or of the app" do
      assert Images.safe_url?("/uploads/a.png")
      assert Images.safe_url?("https://cdn.example.com/a.png")
      refute Images.safe_url?("//evil.org/a.png")
      refute Images.safe_url?("javascript:alert(1)")
      refute Images.safe_url?("data:image/svg+xml,<svg/>")
      refute Images.safe_url?(~s{/a.png" onerror="alert(1)})
    end

    test "is served with its type, and nothing else", %{root: root} do
      {:ok, image} = Images.store(fixture("small.png"))
      File.write!(Path.join(root, "page.html"), "<script></script>")
      plug = LocalPlug.init([])

      conn = LocalPlug.call(build_conn(:get, image.url), plug)
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["image/png"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

      conn = LocalPlug.call(build_conn(:get, "/uploads/page.html"), plug)
      assert get_resp_header(conn, "content-type") == ["application/octet-stream"]
    end
  end

  describe "a canvas's kits" do
    test "are modules that are there: the Images kit, with Storehouse in the deps" do
      assert Hakushi.Kit.check!(Kit) == :ok

      assert_raise ArgumentError, ~r/must be a module/, fn ->
        Hakushi.Kit.check!(Hakushi.Kits.NotThere)
      end
    end
  end

  describe "the kit's node" do
    @image %Storehouse.File{
      key: "2026/10/k-a.png",
      url: "/uploads/2026/10/k-a.png",
      name: "a.png",
      content_type: "image/png",
      bytes: 1,
      width: 1600,
      height: 1000
    }

    test "is as wide as its box, as high as its file says, and 480 at most unasked" do
      assert %{type: "image", x: 10, y: 20, width: 320, height: 200, data: data} =
               Kit.image_node(@image, [10, 20, 320, 0], alt: "A", caption: "B")

      assert %{"pixels" => [1600, 1000], "crop" => [0, 0, 1, 1], "alt" => "A", "caption" => "B"} =
               data

      assert %{width: 480, height: 300} = Kit.image_node(@image, nil)
      assert %{width: 4, height: 3} = Kit.image_node(%{@image | width: 4, height: 3}, [0, 0])
    end

    test "takes a caption, alt text and a crop, and nothing else" do
      data = Kit.image_node(@image, nil).data
      assert {:ok, %{"caption" => "Dusk"}} = Kit.edit("text", %{"value" => " Dusk \n"}, data)

      assert {:ok, %{"alt" => "Piers"}} =
               Kit.edit("style", %{"style" => %{"alt" => "Piers"}}, data)

      assert {:ok, %{"crop" => [0.1, 0, 0.5, 1]}} =
               Kit.edit("crop", %{"crop" => [0.1, 0, 0.5, 1.0]}, data)

      assert :error = Kit.edit("crop", %{"crop" => [0.6, 0, 0.5, 1]}, data)
      assert :error = Kit.edit("crop", %{"crop" => [0, 0, 0, 1]}, data)
      assert :error = Kit.edit("style", %{"style" => %{"url" => "javascript:1"}}, data)
    end

    test "is named by its alt text, else its caption" do
      messages = Hakushi.Messages.for_locale("en")
      node = fn data -> %Hakushi.Node{id: "i", type: "image", data: data} end

      assert Kit.label(node.(%{"alt" => "Piers", "caption" => "Dusk"}), messages) ==
               "Image: Piers"

      assert Kit.label(node.(%{"alt" => "", "caption" => "Dusk"}), messages) == "Image: Dusk"
      assert Kit.label(node.(%{}), messages) == "Image"
    end
  end

  describe "a canvas with images" do
    defp open(query \\ "") do
      {:ok, view, html} = live(build_conn(), "/images" <> query)
      {view, html}
    end

    defp config(html) do
      [config] = Regex.run(~r/data-config="([^"]+)"/, html, capture: :all_but_first)
      config |> String.replace("&quot;", "\"") |> String.replace("&amp;", "&") |> JSON.decode!()
    end

    defp upload(view, name, place) do
      input =
        file_input(view, "#board-files", :hakushi_files, [
          %{name: name, content: File.read!(fixture(name)), type: MIME.from_path(name)}
        ])

      [%{"ref" => ref}] = input.entries
      if place, do: place(view, ref, place)
      render_upload(input, name)
      ref
    end

    defp place(view, ref, {box, parent}) do
      view
      |> element("#board-hook")
      |> render_hook("hakushi:place", %{"ref" => ref, "box" => box, "parent" => parent})
    end

    test "has a tool that picks files, and takes the images of the kit" do
      {_view, html} = open()
      config = config(html)
      assert %{"kit" => "images", "accept" => accept, "urls" => true} = config["files"]
      assert ".webp" in accept and ".jpeg" in accept
      assert [%{"tool" => "image", "mode" => "pick", "key" => "i"}] = config["tools"]
      assert html =~ ~s(data-hakushi-files)
    end

    test "shows an image cropped, with its aspect ratio, and its caption" do
      {view, _html} = open()

      assert :ok =
               edit(view, "board", "photo", "crop", %{
                 "crop" => [0.5, 0, 0.5, 1],
                 "box" => [40, 0, 200, 300]
               })

      assert %{x: 40, width: 200, height: 300} =
               Enum.find(nodes(view, "board"), &(&1.id == "photo"))

      html = render(view)
      assert html =~ ~s(data-hakushi-crop="[0.5,0,0.5,1]")
      assert html =~ ~s(data-hakushi-aspect="0.6666666666666666")
      assert html =~ "width: 200.0%; height: 100.0%; left: -100.0%; top: 0.0%;"
      assert html =~ ~s(loading="lazy")

      # ⌘Z: as it was, the box too.
      assert :ok = undo(view, "board")

      assert %{x: 0, width: 400} = Enum.find(nodes(view, "board"), &(&1.id == "photo"))
      assert render(view) =~ ~s(data-hakushi-crop="[0,0,1,1]")
    end

    test "makes a node of an uploaded image, where the person put it", %{root: root} do
      {view, _html} = open()
      ref = upload(view, "harbour.jpg", {[100, 50, 300, 999], nil})

      assert_push_event(view, "hakushi:file", %{"ref" => ^ref, "id" => id})
      node = Enum.find(nodes(view, "board"), &(&1.id == id))
      # Its width is the box's, its height the file's aspect ratio.
      assert %{type: "image", x: 100, y: 50, width: 300, height: 200} = node

      [url] =
        Regex.run(~r{src="/uploads/([^"]+-harbour\.jpg)"}, render(view), capture: :all_but_first)

      assert url =~ ~r/-harbour\.jpg\z/
      assert File.exists?(Path.join(root, url))
      assert render(view) =~ ~s(data-hakushi-aspect="1.5")
    end

    test "puts an image dropped in a group in it" do
      {view, _html} = open()
      ref = upload(view, "small.png", {[620, 20, 100, 75], "frame"})
      assert_push_event(view, "hakushi:file", %{"ref" => ^ref, "id" => id})
      assert %{parent: "frame"} = Enum.find(nodes(view, "board"), &(&1.id == id))
    end

    test "refuses a file that is not an image, and says so" do
      {view, _html} = open()
      before = length(nodes(view, "board"))
      ref = upload(view, "not-an-image.png", {[0, 0, 100, 100], nil})

      assert_push_event(view, "hakushi:file", %{"ref" => ^ref, "error" => message})
      assert message =~ "not an image"
      assert length(nodes(view, "board")) == before
      assert notice(view, "board") =~ "not an image"
    end

    test "fetches an address only from the hosts the app allows" do
      {view, _html} = open()

      reply =
        view
        |> element("#board-hook")
        |> render_hook("hakushi:paste-url", %{
          "url" => "https://example.org/a.png",
          "ref" => "u1",
          "box" => [0, 0, 100, 100]
        })

      assert reply
      assert_push_event(view, "hakushi:file", %{"ref" => "u1", "error" => message}, 1_000)
      assert message =~ "not allowed"
    end

    test "takes no files when it is read-only" do
      {_view, html} = open("?readonly=true")
      refute html =~ "data-hakushi-files"
      assert config(html)["files"] == nil
    end
  end

  describe "an image on a shared canvas" do
    defp agent,
      do: Context.new(HakushiTest.Issho, %{id: "assistant", name: "Assistant", kind: :agent})

    setup do
      topic = "images#{System.unique_integer([:positive])}"
      {:ok, view, _html} = live(build_conn(), "/images?live=#{topic}&user=ada")
      %{topic: topic, view: view}
    end

    test "is added by an agent from a file of the app's", %{topic: topic, view: view} do
      Application.put_env(:hakushi, Kit,
        files: fn name -> if name == "rope.png", do: {:ok, fixture("rope.png")}, else: :error end
      )

      args = %{"canvas" => "canvas:" <> topic, "file" => "rope.png", "x" => 0, "y" => 400}
      args = Map.merge(args, %{"width" => 200, "alt" => "Rope", "caption" => "Texture"})

      assert {:ok, %{"id" => id, "width" => 200, "height" => 200}} =
               Issho.Tools.call(Hakushi.Issho.tools(), "add_image", args, agent())

      # The others saw its placeholder as it came.
      assert_push_event(view, "hakushi:peer", %{"files" => [[0, 400, 200, 150, 0]]})

      assert %{type: "image", label: "Image: Rope"} =
               Enum.find(nodes(view, "board"), &(&1.id == id))

      assert render(view) =~ ~s(data-hakushi-text="Texture")

      assert {:error, "The app has no file of that name."} =
               Issho.Tools.call(
                 Hakushi.Issho.tools(),
                 "add_image",
                 %{args | "file" => "secrets.txt"},
                 agent()
               )
    end

    test "is not fetched by an agent from an address the app does not allow", %{topic: topic} do
      args = %{
        "canvas" => "canvas:" <> topic,
        "url" => "http://169.254.169.254/latest",
        "x" => 0,
        "y" => 0
      }

      assert {:error, "The app does not take images from that address."} =
               Issho.Tools.call(Hakushi.Issho.tools(), "add_image", args, agent())

      assert {:error, "Say which image" <> _} =
               Issho.Tools.call(
                 Hakushi.Issho.tools(),
                 "add_image",
                 Map.delete(args, "url"),
                 agent()
               )
    end

    test "shows its placeholder to the others while it uploads", %{topic: topic, view: view} do
      {:ok, kenji, _html} = live(build_conn(), "/images?live=#{topic}&user=kenji")

      view
      |> element("#board-hook")
      |> render_hook("hakushi:peer", %{
        "cursor" => [0, 0],
        "files" => [[10, 20, 300, 200, 40], ["x"], [1, 2, 3]]
      })

      assert_push_event(kenji, "hakushi:peer", %{"files" => [[10, 20, 300, 200, 40]]}, 1_000)
    end
  end
end
