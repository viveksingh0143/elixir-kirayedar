defmodule Kirayedar.Migration do
  @moduledoc """
  Helpers for running migrations across all tenants.

  ## Usage

      defmodule MyApp.ReleaseTasks do
        def migrate_tenants do
          Kirayedar.Migration.migrate_all(MyApp.Repo, MyApp.Accounts.Tenant)
        end

        def migrate_specific_tenant(tenant_id) do
          Kirayedar.Migration.migrate(MyApp.Repo, tenant_id)
        end
      end

  ## Telemetry

  Migration operations emit telemetry events that can be used for monitoring:

      :telemetry.attach(
        "kirayedar-migration-handler",
        [:kirayedar, :tenant, :migrate],
        &handle_migration_event/4,
        nil
      )
  """

  require Logger

  @doc """
  Runs migrations for all tenants in the database.

  ## Options

    * `:path` - Custom migrations path (defaults to priv/repo/migrations)
    * `:direction` - Migration direction, `:up` or `:down` (defaults to `:up`)
    * `:all` - Run all pending migrations (defaults to `true`)

  ## Examples

      Kirayedar.Migration.migrate_all(MyApp.Repo, MyApp.Accounts.Tenant)

      Kirayedar.Migration.migrate_all(MyApp.Repo, MyApp.Accounts.Tenant,
        path: "priv/repo/tenant_migrations"
      )
  """
  def migrate_all(repo, tenant_model, opts \\ []) do
    tenants = Kirayedar.scope_global(fn -> repo.all(tenant_model) end)

    Logger.info("Kirayedar.Migration: Starting migrations for #{length(tenants)} tenants")

    results =
      Enum.map(tenants, fn tenant ->
        tenant_id = get_tenant_id(tenant)
        {tenant_id, migrate(repo, tenant_id, opts)}
      end)

    failures = Enum.filter(results, fn {_, result} -> result != :ok end)

    if Enum.empty?(failures) do
      Logger.info("Kirayedar.Migration: Completed migrations for all tenants successfully")
      :ok
    else
      Logger.error("Kirayedar.Migration: Some migrations failed",
        failures: length(failures),
        failed_tenants: Enum.map(failures, fn {tenant_id, _} -> tenant_id end)
      )

      {:error, failures}
    end
  end

  @doc """
  Runs migrations for a specific tenant.

  ## Options

    * `:path` - Custom migrations path (defaults to priv/repo/migrations)
    * `:direction` - Migration direction, `:up` or `:down` (defaults to `:up`)
    * `:all` - Run all pending migrations (defaults to `true`)

  ## Examples

      Kirayedar.Migration.migrate(MyApp.Repo, "acme_corp")

      Kirayedar.Migration.migrate(MyApp.Repo, "acme_corp",
        path: "priv/repo/tenant_migrations",
        direction: :down,
        all: false
      )
  """
  def migrate(repo, tenant_id, opts \\ []) do
    migration_path = opts[:path] || migrations_path(repo)
    direction = opts[:direction] || :up
    all = Keyword.get(opts, :all, true)

    execute_with_telemetry(repo, :migrate, tenant_id, fn ->
      Logger.info("Kirayedar.Migration: Running migrations",
        tenant: tenant_id,
        direction: direction,
        path: migration_path
      )

      Ecto.Migrator.run(
        repo,
        migration_path,
        direction,
        all: all,
        prefix: tenant_id,
        schema_migration_prefix: tenant_id
      )

      Logger.info("Kirayedar.Migration: Completed migrations", tenant: tenant_id)
      :ok
    end)
  rescue
    e ->
      Logger.error("Kirayedar.Migration: Failed to run migrations",
        tenant: tenant_id,
        error: Exception.message(e)
      )

      {:error, e}
  end

  @doc """
  Rolls back the last migration for a specific tenant.

  ## Examples

      Kirayedar.Migration.rollback(MyApp.Repo, "acme_corp")

      Kirayedar.Migration.rollback(MyApp.Repo, "acme_corp", step: 2)
  """
  def rollback(repo, tenant_id, opts \\ []) do
    migration_path = opts[:path] || migrations_path(repo)
    step = opts[:step] || 1

    execute_with_telemetry(repo, :rollback, tenant_id, fn ->
      Logger.info("Kirayedar.Migration: Rolling back migrations",
        tenant: tenant_id,
        step: step
      )

      Ecto.Migrator.run(
        repo,
        migration_path,
        :down,
        step: step,
        prefix: tenant_id,
        schema_migration_prefix: tenant_id
      )

      Logger.info("Kirayedar.Migration: Completed rollback", tenant: tenant_id)
      :ok
    end)
  rescue
    e ->
      Logger.error("Kirayedar.Migration: Failed to rollback",
        tenant: tenant_id,
        error: Exception.message(e)
      )

      {:error, e}
  end

  defp get_tenant_id(tenant) do
    cond do
      Map.has_key?(tenant, :slug) -> tenant.slug
      Map.has_key?(tenant, :id) -> to_string(tenant.id)
      true -> raise "Cannot determine tenant_id from #{inspect(tenant)}"
    end
  end

  defp migrations_path(repo) do
    app = Keyword.fetch!(repo.config(), :otp_app)
    Path.join([Application.app_dir(app), "priv", "repo", "migrations"])
  end

  defp execute_with_telemetry(repo, action, tenant, fun) do
    start_time = System.monotonic_time()
    metadata = %{tenant: tenant, repo: repo, action: action}

    try do
      result = fun.()
      stop_time = System.monotonic_time()

      measurements = %{
        duration: System.convert_time_unit(stop_time - start_time, :native, :millisecond)
      }

      :telemetry.execute([:kirayedar, :tenant, action], measurements, metadata)
      result
    rescue
      e ->
        :telemetry.execute(
          [:kirayedar, :tenant, action, :error],
          %{count: 1},
          Map.put(metadata, :error, e)
        )

        reraise e, __STACKTRACE__
    end
  end
end
