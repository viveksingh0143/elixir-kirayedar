defmodule Kirayedar.PlugTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Kirayedar.Plug, as: KirayedarPlug

  setup do
    Application.put_env(:kirayedar, :admin_host, "admin.example.com")
    Application.put_env(:kirayedar, :primary_domain, "example.com")
    Application.put_env(:kirayedar, :repo, Kirayedar.Test.PostgresRepo)
    Application.put_env(:kirayedar, :tenant_model, Kirayedar.Test.Tenant)

    on_exit(fn ->
      Kirayedar.clear_tenant()
      Application.delete_env(:kirayedar, :admin_host)
      Application.delete_env(:kirayedar, :primary_domain)
    end)

    :ok
  end

  describe "call/2" do
    test "sets tenant from subdomain" do
      conn =
        conn(:get, "/")
        |> put_req_header("host", "acme.example.com")
        |> KirayedarPlug.call(:tenant)

      assert conn.assigns[:tenant] == "acme"
      assert Kirayedar.current_tenant() == "acme"
    end

    test "sets tenant to nil for admin host" do
      conn =
        conn(:get, "/")
        |> put_req_header("host", "admin.example.com")
        |> KirayedarPlug.call(:tenant)

      assert conn.assigns[:tenant] == nil
      assert Kirayedar.current_tenant() == nil
    end

    test "uses custom assign key" do
      conn =
        conn(:get, "/")
        |> put_req_header("host", "acme.example.com")
        |> KirayedarPlug.call(:current_tenant)

      assert conn.assigns[:current_tenant] == "acme"
    end

    test "strips port from host header" do
      conn =
        conn(:get, "/")
        |> put_req_header("host", "acme.example.com:4000")
        |> KirayedarPlug.call(:tenant)

      assert conn.assigns[:tenant] == "acme"
    end
  end
end
