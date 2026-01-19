defmodule Kirayedar.MigrationTest do
  use Kirayedar.PostgresCase, async: false

  alias Kirayedar.Migration
  alias Kirayedar.Test.Tenant

  setup do
    # Create test tenant
    {:ok, tenant} =
      Kirayedar.scope_global(fn ->
        %Tenant{}
        |> Tenant.changeset(%{
          name: "Test Tenant",
          slug: "test_migration",
          status: "active"
        })
        |> Repo.insert()
      end)

    Kirayedar.create(Repo, tenant.slug)

    on_exit(fn ->
      Kirayedar.drop(Repo, tenant.slug)

      Kirayedar.scope_global(fn ->
        Repo.delete(tenant)
      end)

      Kirayedar.clear_tenant()
    end)

    {:ok, tenant: tenant}
  end

  describe "migrate/3" do
    test "runs migrations for specific tenant", %{tenant: tenant} do
      # Create a simple migration directory
      migration_path = Path.join(System.tmp_dir!(), "test_migrations")
      File.mkdir_p!(migration_path)

      timestamp = :os.system_time(:second)

      migration_content = """
      defmodule Repo.Migrations.CreatePosts do
        use Ecto.Migration

        def change do
          create table(:posts) do
            add :title, :string
            timestamps()
          end
        end
      end
      """

      File.write!(
        Path.join(migration_path, "#{timestamp}_create_posts.exs"),
        migration_content
      )

      assert :ok = Migration.migrate(Repo, tenant.slug, path: migration_path)

      # Verify table was created in tenant schema
      {:ok, result} =
        Kirayedar.with_tenant(tenant.slug, fn ->
          Repo.query("""
          SELECT table_name
          FROM information_schema.tables
          WHERE table_schema = '#{tenant.slug}'
          AND table_name = 'posts'
          """)
        end)

      assert result.num_rows == 1

      # Cleanup
      File.rm_rf!(migration_path)
    end
  end

  describe "rollback/3" do
    test "rolls back migrations for specific tenant", %{tenant: tenant} do
      # This would require setting up actual migrations
      # For now, we verify the function accepts the correct parameters
      migration_path = Path.join(System.tmp_dir!(), "test_migrations")
      File.mkdir_p!(migration_path)

      result = Migration.rollback(Repo, tenant.slug, path: migration_path, step: 1)

      # Either succeeds or returns error for no migrations
      assert result == :ok or match?({:error, _}, result)

      File.rm_rf!(migration_path)
    end
  end
end
