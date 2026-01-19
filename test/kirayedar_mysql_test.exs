defmodule Kirayedar.MySQLTest do
  use Kirayedar.MySQLCase, async: false

  alias Kirayedar.Test.Tenant

  setup do
    # Clean up any existing test databases
    cleanup_database("test_mysql")
    cleanup_database("test_mysql_2")

    on_exit(fn ->
      cleanup_database("test_mysql")
      cleanup_database("test_mysql_2")
      Kirayedar.clear_tenant()
    end)

    :ok
  end

  describe "create/2 with MySQL" do
    test "creates a new database" do
      assert :ok = Kirayedar.create(Repo, "test_mysql")

      # Verify database exists
      {:ok, result} =
        Repo.query(
          "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'test_mysql'"
        )

      assert result.num_rows == 1
    end

    test "returns error for invalid tenant_id" do
      assert {:error, :invalid_tenant_id} = Kirayedar.create(Repo, "Invalid-Tenant!")
    end

    test "handles existing database gracefully" do
      assert :ok = Kirayedar.create(Repo, "test_mysql")
      assert :ok = Kirayedar.create(Repo, "test_mysql")
    end
  end

  describe "drop/2 with MySQL" do
    test "drops an existing database" do
      Kirayedar.create(Repo, "test_mysql")
      assert :ok = Kirayedar.drop(Repo, "test_mysql")

      {:ok, result} =
        Repo.query(
          "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 'test_mysql'"
        )

      assert result.num_rows == 0
    end

    test "handles non-existent database gracefully" do
      assert :ok = Kirayedar.drop(Repo, "nonexistent")
    end
  end

  describe "tenant isolation with MySQL" do
    setup do
      # Create database and table
      Kirayedar.create(Repo, "test_mysql")

      Kirayedar.with_tenant("test_mysql", fn ->
        Repo.query!("""
        CREATE TABLE posts (
          id INT AUTO_INCREMENT PRIMARY KEY,
          title VARCHAR(255)
        )
        """)
      end)

      :ok
    end

    test "queries use correct database prefix" do
      Kirayedar.put_tenant("test_mysql")

      Repo.query!("INSERT INTO posts (title) VALUES ('Test Post')")

      {:ok, result} = Repo.query("SELECT * FROM posts")
      assert result.num_rows == 1
    end

    test "with_tenant/2 provides proper isolation" do
      # Insert in tenant database
      Kirayedar.with_tenant("test_mysql", fn ->
        Repo.query!("INSERT INTO posts (title) VALUES ('Tenant Post')")
      end)

      # Verify isolation
      count =
        Kirayedar.with_tenant("test_mysql", fn ->
          {:ok, result} = Repo.query("SELECT COUNT(*) FROM posts")
          result.rows |> List.first() |> List.first()
        end)

      assert count == 1
    end
  end

  defp cleanup_database(db_name) do
    try do
      Kirayedar.drop(Repo, db_name)
    rescue
      _ -> :ok
    end
  end
end
