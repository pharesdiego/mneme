defmodule MnemeIntegration.EctoSchemaTest do
  use ExUnit.Case
  use Mneme

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field(:email, :string)
      timestamps()
    end
  end

  test "should exclude autogenerated fields" do
    auto_assert {:ok, %User{email: "user@example.org"}} <- create_user(email: "user@example.org")
  end

  # TODO: Set up a Repo to ensure these fields are being properly set.
  defp create_user(attrs) do
    now = NaiveDateTime.utc_now()

    attrs =
      Enum.into(attrs, %{
        id: 1,
        inserted_at: now,
        updated_at: now
      })

    user =
      User
      |> struct(attrs)
      |> Map.update!(:__meta__, &Map.put(&1, :state, :loaded))

    {:ok, user}
  end
end
