defmodule HakushiTest.Blog.User do
  @moduledoc "A schema of the Ecto importer's tests."
  use Ecto.Schema

  schema "users" do
    field :email, :string
    field :roles, {:array, :string}
    has_many :posts, HakushiTest.Blog.Post, foreign_key: :author_id
    timestamps(type: :utc_datetime)
  end
end

defmodule HakushiTest.Blog.Post do
  @moduledoc "A schema of the Ecto importer's tests."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "posts" do
    field :title, :string, source: :post_title
    field :state, Ecto.Enum, values: [:draft, :published]
    field :body, :map
    belongs_to :author, HakushiTest.Blog.User
    many_to_many :tags, HakushiTest.Blog.Tag, join_through: "posts_tags"
  end
end

defmodule HakushiTest.Blog.Tag do
  @moduledoc "A schema of the Ecto importer's tests."
  use Ecto.Schema

  schema "tags" do
    field :name, :string
  end
end

defmodule HakushiTest.Blog.Comment do
  @moduledoc "A schema of the Ecto importer's tests."
  use Ecto.Schema

  schema "comments" do
    field :text, :string
    field :rating, :decimal
    belongs_to :post, HakushiTest.Blog.Post, type: :binary_id
    belongs_to :account, HakushiTest.Billing.Account
  end
end

defmodule HakushiTest.Billing.Account do
  @moduledoc "A schema of another prefix, for the Ecto importer's tests."
  use Ecto.Schema

  @schema_prefix "billing"
  schema "accounts" do
    field :plan, :string
  end
end

defmodule HakushiTest.Blog.Settings do
  @moduledoc "An embedded schema, which the Ecto importer leaves out."
  use Ecto.Schema

  embedded_schema do
    field :theme, :string
  end
end
