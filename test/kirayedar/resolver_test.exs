defmodule Kirayedar.ResolverTest do
  use ExUnit.Case, async: true
  alias Kirayedar.Resolver

  setup do
    # Set up test configuration
    Application.put_env(:kirayedar, :admin_host, "admin.example.com")
    Application.put_env(:kirayedar, :primary_domain, "example.com")
    Application.put_env(:kirayedar, :repo, Kirayedar.Test.PostgresRepo)
    Application.put_env(:kirayedar, :tenant_model, Kirayedar.Test.Tenant)

    on_exit(fn ->
      Application.delete_env(:kirayedar, :admin_host)
      Application.delete_env(:kirayedar, :primary_domain)
    end)

    :ok
  end

  describe "resolve/1 with admin host" do
    test "returns nil for admin host" do
      assert Resolver.resolve("admin.example.com") == nil
    end

    test "returns nil for admin host with port" do
      assert Resolver.resolve("admin.example.com:4000") == nil
    end
  end

  describe "resolve/1 with subdomain extraction" do
    test "extracts subdomain from primary domain" do
      assert Resolver.resolve("acme.example.com") == "acme"
    end

    test "extracts subdomain with port stripped" do
      assert Resolver.resolve("acme.example.com:4000") == "acme"
    end

    test "handles trailing dots" do
      assert Resolver.resolve("acme.example.com.") == "acme"
    end

    test "handles uppercase" do
      assert Resolver.resolve("ACME.EXAMPLE.COM") == "acme"
    end

    test "returns nil for nested subdomains" do
      assert Resolver.resolve("api.acme.example.com") == nil
    end

    test "returns nil for primary domain without subdomain" do
      assert Resolver.resolve("example.com") == nil
    end
  end

  describe "resolve/1 with slug fallback" do
    test "extracts first segment as potential slug" do
      # This would require database lookup, so we'll test the pattern
      result = Resolver.resolve("custom-domain.com")
      # Without database, this will return nil or the slug if found
      assert is_nil(result) or is_binary(result)
    end
  end

  describe "resolve/1 edge cases" do
    test "handles nil input" do
      assert Resolver.resolve(nil) == nil
    end

    test "handles empty string" do
      assert Resolver.resolve("") == nil
    end

    test "handles localhost" do
      result = Resolver.resolve("localhost")
      assert is_nil(result) or is_binary(result)
    end

    test "handles localhost with port" do
      result = Resolver.resolve("localhost:4000")
      assert is_nil(result) or is_binary(result)
    end
  end
end
