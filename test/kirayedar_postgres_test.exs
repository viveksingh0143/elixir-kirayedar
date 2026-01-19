defmodule Kirayedar.PostgresTest do
  use Kirayedar.PostgresCase, async: false

  alias Kirayedar.Test.Tenant

  setup do
    # Clean up any existing test tenants
    cleanup_tenant("test_pg")
    cleanup_tenant("test_pg_2")

    on_exit(fn ->
      cleanup_tenant("test_pg")
      cleanup_tenant("test_pg_2")
      Kirayedar.clear_tenant()
    end)

    :ok
  end

  describe "create/2 with PostgreSQL" do
    test "creates a new schema" do
      assert :ok = Kirayedar.create(Repo, "test_pg")

      # Verify schema exists
      {:ok, result} =
        Repo.query(
          "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'test_pg'"
        )

      assert result.num_rows == 1
    end

    test "returns error for invalid tenant_id" do
      assert {:error, :invalid_tenant_id} = Kirayedar.create(Repo, "Invalid-Tenant!")
    end

    test "handles existing schema gracefully" do
      assert :ok = Kirayedar.create(Repo, "test_pg")
      assert :ok = Kirayedar.create(Repo, "test_pg")
    end
  end

  describe "drop/2 with PostgreSQL" do
    test "drops an existing schema" do
      Kirayedar.create(Repo, "test_pg")
      assert :ok = Kirayedar.drop(Repo, "test_pg")

      {:ok, result} =
        Repo.query(
          "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'test_pg'"
        )

      assert result.num_rows == 0
    end

    test "handles non-existent schema gracefully" do
      assert :ok = Kirayedar.drop(Repo, "nonexistent")
    end
  end

  describe "tenant isolation with PostgreSQL" do
    setup do
      # Create tenant and table
      Kirayedar.create(Repo, "test_pg")

      Kirayedar.with_tenant("test_pg", fn ->
        Repo.query!("""
        CREATE TABLE posts (
          id SERIAL PRIMARY KEY,
          title VARCHAR(255)
        )
        """)
      end)

      :ok
    end

    test "queries use correct schema prefix" do
      Kirayedar.put_tenant("test_pg")

      Repo.query!("INSERT INTO posts (title) VALUES ('Test Post')")

      {:ok, result} = Repo.query("SELECT * FROM posts")
      assert result.num_rows == 1

      # Verify it's isolated from public schema
      Kirayedar.clear_tenant()

      assert_raise Postgrex.Error, fn ->
        Repo.query!("SELECT * FROM posts")
      end
    end

    test "with_tenant/2 provides proper isolation" do
      # Insert in tenant schema
      Kirayedar.with_tenant("test_pg", fn ->
        Repo.query!("INSERT INTO posts (title) VALUES ('Tenant Post')")
      end)

      # Verify isolation
      count =
        Kirayedar.with_tenant("test_pg", fn ->
          {:ok, result} = Repo.query("SELECT COUNT(*) FROM posts")
          result.rows |> List.first() |> List.first()
        end)

      assert count == 1
    end
  end

  defp cleanup_tenant(tenant_id) do
    try do
      Kirayedar.drop(Repo, tenant_id)
    rescue
      _ -> :ok
    end
  end
end
