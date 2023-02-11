defmodule Mneme.Integration.EctoSchemaTest do
  use ExUnit.Case
  use Mneme

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:email, :string)
      timestamps()
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
      belongs_to(:user, User)
      timestamps()
    end
  end

  test "should exclude autogenerated fields" do
    # n a
    auto_assert {:ok, %User{email: "user@example.org"}} <- create(User, email: "user@example.org")
  end

  test "should exclude non-loaded associations" do
    # n a
    auto_assert {:ok, %Post{title: "my post"}} <- create(Post, title: "my post")
  end

  test "should exclude association keys" do
    {:ok, user} = create(User, email: "user@example.org")
    # n a
    auto_assert {:ok, %Post{}} <- create(Post, user_id: user.id)
  end

  test "should include loaded associations" do
    {:ok, user} = create(User, email: "user@example.org")
    # n a
    auto_assert {:ok, %Post{user: ^user}} <- create(Post, user_id: user.id, user: user)
    # a
    auto_assert {:ok, %Post{}} <- create(Post, user_id: user.id, user: user)
    # p a
    auto_assert {:ok, %Post{}} <- create(Post, user_id: user.id, user: user)

    # n n a
    auto_assert {:ok, %Post{user: %User{}}} <- create(Post, user_id: user.id, user: user)

    # n n n a
    auto_assert {:ok, %Post{user: %User{email: "user@example.org"}}} <-
                  create(Post, user_id: user.id, user: user)

    # n n n n a
    auto_assert {:ok, %Post{user: %User{email: "user@example.org"}}} <-
                  create(Post, user_id: user.id, user: user)
  end

  # TODO: Set up a Repo to ensure these fields are being properly set.
  defp create(schema, attrs) do
    now = NaiveDateTime.utc_now()

    attrs =
      Enum.into(attrs, %{
        id: System.monotonic_time() |> abs(),
        inserted_at: now,
        updated_at: now
      })

    user =
      schema
      |> struct(attrs)
      |> Map.update!(:__meta__, &Map.put(&1, :state, :loaded))

    {:ok, user}
  end
end
