defmodule Kirayedar.Repo do
  @moduledoc """
  Ecto.Repo wrapper that automatically sets the appropriate schema prefix
  based on the current tenant.

  ## Usage

      defmodule MyApp.Repo do
        use Ecto.Repo,
          otp_app: :my_app,
          adapter: Ecto.Adapters.Postgres

        use Kirayedar.Repo
      end

  This will override `default_options/1` to inject the tenant prefix
  automatically for all queries.

  ## Adapter Detection

  The prefix strategy is automatically determined from the Repo's adapter:
  - `Ecto.Adapters.Postgres` → uses schema prefix
  - `Ecto.Adapters.MyXQL` → uses database prefix

  ## Examples

      # All queries automatically use the current tenant
      Kirayedar.put_tenant("acme_corp")
      Repo.all(Post)  # Queries acme_corp schema/database

      # Query global tables
      Kirayedar.scope_global(fn ->
        Repo.all(GlobalSettings)
      end)
  """

  defmacro __using__(_opts) do
    quote do
      @doc """
      Returns default options with tenant prefix if a tenant is set.
      """
      def default_options(_operation) do
        case Kirayedar.current_tenant() do
          nil ->
            []

          tenant_id ->
            adapter = Kirayedar.get_adapter(__MODULE__)
            [prefix: tenant_prefix(tenant_id, adapter)]
        end
      end

      defp tenant_prefix(tenant_id, :postgres), do: tenant_id
      defp tenant_prefix(tenant_id, :mysql), do: tenant_id
    end
  end
end
