defmodule Hakushi.SchemaFamiliesTest do
  # The families of the app's own change the application's config.
  use ExUnit.Case, async: false

  alias Hakushi.Kits.Schema

  setup do
    on_exit(fn -> Application.delete_env(:hakushi, Schema) end)
  end

  test "the app adds families, and changes Hakushi's" do
    Application.put_env(:hakushi, Schema, families: %{"ltree" => "text", "money" => "money"})

    assert Schema.family("ltree") == "text"
    assert Schema.family("money") == "money"
    assert Schema.family("numeric") == "decimal"
  end
end
