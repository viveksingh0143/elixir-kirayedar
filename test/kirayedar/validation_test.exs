defmodule Kirayedar.ValidationTest do
  use ExUnit.Case, async: true

  describe "tenant_id validation" do
    test "accepts valid tenant IDs" do
      valid_ids = [
        "simple",
        "with_underscores",
        "with123numbers",
        "a",
        "very_long_tenant_name_with_many_underscores_123"
      ]

      for tenant_id <- valid_ids do
        assert :ok = Kirayedar.create(MockRepo, tenant_id)
      end
    end

    test "rejects invalid tenant IDs" do
      invalid_ids = [
        "has-dashes",
        "has spaces",
        "Has_Uppercase",
        "has.dots",
        "has/slashes",
        "has\\backslashes",
        # SQL injection attempt
        "'; DROP TABLE users; --",
        "",
        "tenant;",
        "../../../etc/passwd"
      ]

      for tenant_id <- invalid_ids do
        assert {:error, :invalid_tenant_id} = Kirayedar.create(MockRepo, tenant_id)
      end
    end
  end
end

# Mock repo for validation tests
defmodule MockRepo do
  def query(_sql), do: {:ok, %{num_rows: 0, rows: []}}
  def __adapter__, do: Ecto.Adapters.Postgres
end
