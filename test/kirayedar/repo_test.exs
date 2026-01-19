defmodule Kirayedar.RepoTest do
  use Kirayedar.PostgresCase, async: false

  setup do
    # Create test tenant schema
    Kirayedar.create(Repo, "test_repo")

    Kirayedar.with_tenant("test_repo", fn ->
      Repo.query!("""
      CREATE TABLE IF NOT EXISTS articles (
        id SERIAL PRIMARY KEY,
        title VARCHAR(255),
        content TEXT
      )
      """)
    end)

    on_exit(fn ->
      Kirayedar.drop(Repo, "test_repo")
      Kirayedar.clear_tenant()
    end)

    :ok
  end

  describe "default_options/1" do
    test "includes prefix when tenant is set" do
      Kirayedar.put_tenant("test_repo")

      Repo.query!("INSERT INTO articles (title, content) VALUES ('Test', 'Content')")

      # Verify it was inserted in the tenant schema
      {:ok, result} =
        Repo.query("""
        SELECT * FROM test_repo.articles WHERE title = 'Test'
        """)

      assert result.num_rows == 1
    end

    test "uses public schema when no tenant is set" do
      Kirayedar.clear_tenant()

      # This should fail as articles table doesn't exist in public
      assert_raise Postgrex.Error, fn ->
        Repo.query!("SELECT * FROM articles")
      end
    end

    test "scope_global bypasses tenant prefix" do
      Kirayedar.put_tenant("test_repo")

      # Create a global table
      Kirayedar.scope_global(fn ->
        Repo.query!("""
        CREATE TABLE IF NOT EXISTS global_settings (
          id SERIAL PRIMARY KEY,
          key VARCHAR(255),
          value TEXT
        )
        """)

        Repo.query!("INSERT INTO global_settings (key, value) VALUES ('theme', 'dark')")
      end)

      # Verify we can access it with scope_global
      result =
        Kirayedar.scope_global(fn ->
          {:ok, res} = Repo.query("SELECT * FROM global_settings")
          res.num_rows
        end)

      assert result == 1

      # Cleanup
      Kirayedar.scope_global(fn ->
        Repo.query!("DROP TABLE IF EXISTS global_settings")
      end)
    end
  end
end
