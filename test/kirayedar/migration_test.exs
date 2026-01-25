# test/kirayedar/migration_test.exs - COMPLETE REWRITE
defmodule Kirayedar.MigrationTest do
  use Kirayedar.PostgresCase, async: false

  alias Kirayedar.Migration
  alias Kirayedar.Test.Tenant

  @migration_dir Path.join(System.tmp_dir!(), "kirayedar_test_migrations")

  setup do
    # Clean migration directory
    File.rm_rf!(@migration_dir)
    File.mkdir_p!(@migration_dir)

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
      File.rm_rf!(@migration_dir)
    end)

    {:ok, tenant: tenant}
  end

  describe "migrate/3" do
    test "runs migrations for specific tenant", %{tenant: tenant} do
      create_test_migration("create_posts", """
      defmodule Repo.Migrations.CreatePosts do
        use Ecto.Migration

        def change do
          create table(:posts) do
            add :title, :string
            add :content, :text
            timestamps()
          end
        end
      end
      """)

      assert :ok = Migration.migrate(Repo, tenant.slug, path: @migration_dir)

      # Verify table was created in tenant schema
      assert table_exists?(tenant.slug, "posts")
      assert table_exists?(tenant.slug, "schema_migrations")
    end

    test "handles migration errors gracefully", %{tenant: tenant} do
      create_test_migration("bad_migration", """
      defmodule Repo.Migrations.BadMigration do
        use Ecto.Migration

        def change do
          execute "INVALID SQL HERE"
        end
      end
      """)

      assert {:error, _} = Migration.migrate(Repo, tenant.slug, path: @migration_dir)
    end

    test "respects :all option", %{tenant: tenant} do
      create_test_migration("first_migration", """
      defmodule Repo.Migrations.FirstMigration do
        use Ecto.Migration
        def change, do: create table(:first)
      end
      """)

      create_test_migration("second_migration", """
      defmodule Repo.Migrations.SecondMigration do
        use Ecto.Migration
        def change, do: create table(:second)
      end
      """)

      assert :ok = Migration.migrate(Repo, tenant.slug, path: @migration_dir, all: true)

      assert table_exists?(tenant.slug, "first")
      assert table_exists?(tenant.slug, "second")
    end
  end

  describe "rollback/3" do
    setup %{tenant: tenant} do
      create_test_migration("create_articles", """
      defmodule Repo.Migrations.CreateArticles do
        use Ecto.Migration

        def change do
          create table(:articles) do
            add :title, :string
            timestamps()
          end
        end
      end
      """)

      Migration.migrate(Repo, tenant.slug, path: @migration_dir)
      :ok
    end

    test "rolls back last migration", %{tenant: tenant} do
      assert table_exists?(tenant.slug, "articles")

      assert :ok = Migration.rollback(Repo, tenant.slug, path: @migration_dir, step: 1)

      refute table_exists?(tenant.slug, "articles")
    end

    test "rolls back multiple steps", %{tenant: tenant} do
      create_test_migration("create_comments", """
      defmodule Repo.Migrations.CreateComments do
        use Ecto.Migration
        def change, do: create table(:comments)
      end
      """)

      Migration.migrate(Repo, tenant.slug, path: @migration_dir)

      assert :ok = Migration.rollback(Repo, tenant.slug, path: @migration_dir, step: 2)

      refute table_exists?(tenant.slug, "articles")
      refute table_exists?(tenant.slug, "comments")
    end
  end

  describe "migrate_all/3" do
    test "migrates all tenants successfully" do
      # Create multiple tenants
      tenants =
        Kirayedar.scope_global(fn ->
          for i <- 1..3 do
            {:ok, tenant} =
              %Tenant{}
              |> Tenant.changeset(%{name: "Tenant #{i}", slug: "tenant_#{i}", status: "active"})
              |> Repo.insert()

            Kirayedar.create(Repo, tenant.slug)
            tenant
          end
        end)

      create_test_migration("create_shared_table", """
      defmodule Repo.Migrations.CreateSharedTable do
        use Ecto.Migration
        def change, do: create table(:shared)
      end
      """)

      assert :ok = Migration.migrate_all(Repo, Tenant, path: @migration_dir)

      # Verify all tenants have the table
      Enum.each(tenants, fn tenant ->
        assert table_exists?(tenant.slug, "shared")
      end)

      # Cleanup
      Enum.each(tenants, fn tenant ->
        Kirayedar.drop(Repo, tenant.slug)
        Kirayedar.scope_global(fn -> Repo.delete(tenant) end)
      end)
    end

    test "reports failures but continues with other tenants" do
      tenants =
        Kirayedar.scope_global(fn ->
          for i <- 1..2 do
            {:ok, tenant} =
              %Tenant{}
              |> Tenant.changeset(%{
                name: "Tenant #{i}",
                slug: "fail_tenant_#{i}",
                status: "active"
              })
              |> Repo.insert()

            # Only create schema for first tenant
            if i == 1, do: Kirayedar.create(Repo, tenant.slug)
            tenant
          end
        end)

      create_test_migration("test_migration", """
      defmodule Repo.Migrations.TestMigration do
        use Ecto.Migration
        def change, do: create table(:test)
      end
      """)

      # Should return error with failures listed
      assert {:error, failures} = Migration.migrate_all(Repo, Tenant, path: @migration_dir)
      assert length(failures) == 1
      assert {"fail_tenant_2", _error} = List.first(failures)

      # Cleanup
      Enum.each(tenants, fn tenant ->
        Kirayedar.drop(Repo, tenant.slug)
        Kirayedar.scope_global(fn -> Repo.delete(tenant) end)
      end)
    end
  end

  # Helper Functions
  defp create_test_migration(name, content) do
    timestamp = :os.system_time(:second)
    filename = "#{timestamp}_#{name}.exs"
    File.write!(Path.join(@migration_dir, filename), content)
  end

  defp table_exists?(schema, table_name) do
    {:ok, result} =
      Repo.query("""
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = '#{schema}'
      AND table_name = '#{table_name}'
      """)

    result.num_rows == 1
  end
end
