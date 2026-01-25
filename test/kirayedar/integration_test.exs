defmodule Kirayedar.IntegrationTest do
  use Kirayedar.PostgresCase, async: false

  @moduletag :integration

  test "complete tenant lifecycle" do
    # 1. Create tenant record
    tenant =
      Kirayedar.scope_global(fn ->
        %Tenant{name: "Integration Test", slug: "integration_test"}
        |> Tenant.changeset(%{status: "pending"})
        |> Repo.insert!()
      end)

    # 2. Create schema
    assert :ok = Kirayedar.create(Repo, tenant.slug)

    # 3. Verify schema exists
    assert {:ok, %{schema_exists: true}} = Kirayedar.health_check(Repo, tenant.slug)

    # 4. Run migrations
    assert :ok = Kirayedar.Migration.migrate(Repo, tenant.slug)

    # 5. Insert data
    Kirayedar.with_tenant(tenant.slug, fn ->
      nil
      # Your test data insertion
    end)

    # 6. Verify isolation
    Kirayedar.with_tenant("different_tenant", fn ->
      nil
      # Verify data doesn't leak
    end)

    # 7. Cleanup
    assert :ok = Kirayedar.drop(Repo, tenant.slug)
    Kirayedar.scope_global(fn -> Repo.delete(tenant) end)
  end
end
