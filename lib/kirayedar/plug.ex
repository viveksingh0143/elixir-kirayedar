defmodule Kirayedar.Plug do
  @moduledoc """
  Plug for intercepting incoming requests and setting tenant context.

  Automatically resolves the tenant from the request host and updates
  both the Kirayedar process state and connection assigns.

  ## Usage

  In your Phoenix endpoint or router:

      plug Kirayedar.Plug

  Or with options:

      plug Kirayedar.Plug, assign_key: :current_tenant

  ## Configuration

      config :kirayedar,
        repo: MyApp.Repo,
        primary_domain: "example.com",
        admin_host: "admin.example.com",
        tenant_model: MyApp.Accounts.Tenant
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @default_assign_key :tenant

  @impl true
  def init(opts) do
    Keyword.get(opts, :assign_key, @default_assign_key)
  end

  @impl true
  def call(conn, assign_key) do
    host = get_host(conn)
    tenant_id = Kirayedar.Resolver.resolve(host)

    Kirayedar.put_tenant(tenant_id)

    conn
    |> assign(assign_key, tenant_id)
    |> log_tenant_resolution(tenant_id, host)
  end

  defp get_host(conn) do
    case get_req_header(conn, "host") do
      [host | _] -> host
      [] -> conn.host
    end
  end

  defp log_tenant_resolution(conn, tenant_id, host) do
    Logger.metadata(tenant: tenant_id, host: host)

    Logger.debug("Kirayedar.Plug: Tenant resolved",
      tenant: tenant_id || "none",
      host: host,
      path: conn.request_path
    )

    conn
  end
end
