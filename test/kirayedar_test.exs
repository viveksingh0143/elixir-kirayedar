defmodule KirayedarTest do
  use ExUnit.Case, async: false
  doctest Kirayedar

  describe "process dictionary management" do
    test "current_tenant/0 returns nil initially" do
      assert Kirayedar.current_tenant() == nil
    end

    test "put_tenant/1 sets the current tenant" do
      assert :ok = Kirayedar.put_tenant("test_tenant")
      assert Kirayedar.current_tenant() == "test_tenant"
    end

    test "put_tenant/1 with nil clears the tenant" do
      Kirayedar.put_tenant("test_tenant")
      assert :ok = Kirayedar.put_tenant(nil)
      assert Kirayedar.current_tenant() == nil
    end

    test "clear_tenant/0 removes the current tenant" do
      Kirayedar.put_tenant("test_tenant")
      assert :ok = Kirayedar.clear_tenant()
      assert Kirayedar.current_tenant() == nil
    end
  end

  describe "with_tenant/2" do
    test "executes function with tenant context and restores previous" do
      Kirayedar.put_tenant("original")

      result =
        Kirayedar.with_tenant("temporary", fn ->
          assert Kirayedar.current_tenant() == "temporary"
          :success
        end)

      assert result == :success
      assert Kirayedar.current_tenant() == "original"
    end

    test "restores nil when no previous tenant" do
      Kirayedar.clear_tenant()

      Kirayedar.with_tenant("temporary", fn ->
        assert Kirayedar.current_tenant() == "temporary"
      end)

      assert Kirayedar.current_tenant() == nil
    end
  end

  describe "scope_global/1" do
    test "executes function without tenant context" do
      Kirayedar.put_tenant("test_tenant")

      result =
        Kirayedar.scope_global(fn ->
          assert Kirayedar.current_tenant() == nil
          :global_access
        end)

      assert result == :global_access
      assert Kirayedar.current_tenant() == "test_tenant"
    end

    test "handles errors and restores tenant" do
      Kirayedar.put_tenant("test_tenant")

      assert_raise RuntimeError, fn ->
        Kirayedar.scope_global(fn ->
          raise "test error"
        end)
      end

      assert Kirayedar.current_tenant() == "test_tenant"
    end
  end

  describe "get_adapter/1" do
    test "detects Postgres adapter" do
      adapter = Kirayedar.get_adapter(Kirayedar.Test.PostgresRepo)
      assert adapter == :postgres
    end

    test "detects MySQL adapter" do
      adapter = Kirayedar.get_adapter(Kirayedar.Test.MySQLRepo)
      assert adapter == :mysql
    end
  end
end
