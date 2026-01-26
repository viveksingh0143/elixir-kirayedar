defmodule Kirayedar do
  @moduledoc """
  Kirayedar - Multi-tenancy library for Elixir/Phoenix.

  Provides schema-based isolation using PostgreSQL schemas or MySQL databases.
  Manages tenant state through the process dictionary and provides DDL operations.

  ## Configuration

      config :kirayedar,
        repo: MyApp.Repo,
        primary_domain: "example.com",
        admin_host: "admin.example.com",
        tenant_model: MyApp.Accounts.Tenant,
        adapter: :postgres  # or :mysql (optional - auto-detected from repo)

  ## Usage

      # Create a tenant
      Kirayedar.create(repo, "tenant_slug")

      # Drop a tenant
      Kirayedar.drop(repo, "tenant_slug")

      # Get current tenant
      Kirayedar.current_tenant()

      # Set current tenant
      Kirayedar.put_tenant("tenant_slug")

      # Run code without tenant scope
      Kirayedar.scope_global(fn -> Repo.all(GlobalTable) end)

      # Health check
      Kirayedar.health_check(repo, "tenant_slug")

  ## Telemetry Events

  Kirayedar emits the following telemetry events:

    * `[:kirayedar, :tenant, :create]` - Tenant schema creation
    * `[:kirayedar, :tenant, :drop]` - Tenant schema deletion
    * `[:kirayedar, :tenant, :migrate]` - Tenant migration execution
    * `[:kirayedar, :tenant, :create, :error]` - Errors during creation
    * `[:kirayedar, :tenant, :drop, :error]` - Errors during deletion
    * `[:kirayedar, :tenant, :migrate, :error]` - Errors during migration

  Each success event includes measurements: `%{duration: milliseconds}`
  Each event includes metadata: `%{tenant: string, repo: module, action: atom}`
  """

  require Logger

  @type tenant_id :: String.t() | nil
  @type repo :: module()

  @tenant_key :kirayedar_current_tenant

  # ============================================================================
  # Process Dictionary Management
  # ============================================================================

  @doc """
  Gets the current tenant from the process dictionary.

  Returns `nil` if no tenant is set.

  ## Examples

      iex> Kirayedar.current_tenant()
      nil

      iex> Kirayedar.put_tenant("acme_corp")
      iex> Kirayedar.current_tenant()
      "acme_corp"
  """
  @spec current_tenant() :: tenant_id()
  def current_tenant do
    Process.get(@tenant_key)
  end

  @doc """
  Sets the current tenant in the process dictionary.

  When set to `nil`, clears the tenant context.

  ## Examples

      iex> Kirayedar.put_tenant("acme_corp")
      :ok

      iex> Kirayedar.put_tenant(nil)
      :ok
  """
  @spec put_tenant(tenant_id()) :: :ok
  def put_tenant(nil) do
    Process.delete(@tenant_key)
    :ok
  end

  def put_tenant(tenant_id) when is_binary(tenant_id) do
    Process.put(@tenant_key, tenant_id)
    :ok
  end

  @doc """
  Clears the current tenant from the process dictionary.

  Equivalent to `put_tenant(nil)`.

  ## Examples

      iex> Kirayedar.put_tenant("acme_corp")
      iex> Kirayedar.clear_tenant()
      :ok
      iex> Kirayedar.current_tenant()
      nil
  """
  @spec clear_tenant() :: :ok
  def clear_tenant do
    Process.delete(@tenant_key)
    :ok
  end

  # ============================================================================
  # Scoping Functions
  # ============================================================================

  @doc """
  Runs a block of code without any tenant prefix.

  Useful for querying global tables from within a tenant request.
  Automatically restores the previous tenant context after execution,
  even if an exception is raised.

  ## Examples

      # Query global settings while in tenant context
      Kirayedar.put_tenant("acme_corp")

      settings = Kirayedar.scope_global(fn ->
        Repo.all(GlobalSettings)
      end)

      # Access shared reference data
      country = Kirayedar.scope_global(fn ->
        Repo.get(Country, "US")
      end)

      # Still in tenant context
      Kirayedar.current_tenant()  # => "acme_corp"
  """
  @spec scope_global((-> any())) :: any()
  def scope_global(fun) when is_function(fun, 0) do
    current = current_tenant()
    put_tenant(nil)

    try do
      fun.()
    after
      put_tenant(current)
    end
  end

  @doc """
  Executes a function within the context of a specific tenant.

  Automatically restores the previous tenant context after execution,
  even if an exception is raised.

  ## Examples

      iex> Kirayedar.with_tenant("acme_corp", fn ->
      ...>   MyApp.Repo.all(MyApp.Post)
      ...> end)
      [%MyApp.Post{}, ...]

      # Nested tenant contexts
      Kirayedar.with_tenant("tenant_a", fn ->
        # Working in tenant_a

        Kirayedar.with_tenant("tenant_b", fn ->
          # Temporarily in tenant_b
        end)

        # Back to tenant_a
      end)
  """
  @spec with_tenant(tenant_id(), (-> any())) :: any()
  def with_tenant(tenant_id, fun) when is_function(fun, 0) do
    previous_tenant = current_tenant()
    put_tenant(tenant_id)

    try do
      fun.()
    after
      put_tenant(previous_tenant)
    end
  end

  # ============================================================================
  # Tenant DDL Operations
  # ============================================================================

  @doc """
  Creates a new tenant schema/database.

  ## Options

  This function accepts no options currently but may in future versions.

  ## Examples

      iex> Kirayedar.create(MyApp.Repo, "acme_corp")
      :ok

      iex> Kirayedar.create(MyApp.Repo, "invalid slug!")
      {:error, :invalid_tenant_id}

      # Safe to call multiple times
      iex> Kirayedar.create(MyApp.Repo, "acme_corp")
      :ok
      iex> Kirayedar.create(MyApp.Repo, "acme_corp")
      :ok

  ## Telemetry

  Emits `[:kirayedar, :tenant, :create]` event with:
  - Measurements: `%{duration: milliseconds}`
  - Metadata: `%{tenant: tenant_id, repo: repo, action: :create}`
  """
  @spec create(repo(), String.t()) :: :ok | {:error, term()}
  def create(repo, tenant_id) when is_binary(tenant_id) do
    with :ok <- validate_tenant_id(tenant_id),
         adapter <- get_adapter(repo),
         sql <- create_sql(adapter, tenant_id) do
      execute_with_telemetry(repo, :create, tenant_id, fn ->
        execute_ddl(repo, sql, tenant_id, :create)
      end)
    end
  end

  @doc """
  Drops an existing tenant schema/database.

  **Warning**: This operation cannot be undone. All data in the tenant
  schema/database will be permanently deleted.

  ## Examples

      iex> Kirayedar.drop(MyApp.Repo, "acme_corp")
      :ok

      # Safe to call even if schema doesn't exist
      iex> Kirayedar.drop(MyApp.Repo, "nonexistent")
      :ok

  ## Telemetry

  Emits `[:kirayedar, :tenant, :drop]` event with:
  - Measurements: `%{duration: milliseconds}`
  - Metadata: `%{tenant: tenant_id, repo: repo, action: :drop}`
  """
  @spec drop(repo(), String.t()) :: :ok | {:error, term()}
  def drop(repo, tenant_id) when is_binary(tenant_id) do
    with :ok <- validate_tenant_id(tenant_id),
         adapter <- get_adapter(repo),
         sql <- drop_sql(adapter, tenant_id) do
      execute_with_telemetry(repo, :drop, tenant_id, fn ->
        execute_ddl(repo, sql, tenant_id, :drop)
      end)
    end
  end

  @doc """
  Creates a tenant and runs migrations in a coordinated way.

  If migration fails, the schema is automatically dropped to maintain
  consistency. This is useful for ensuring tenants are always fully
  initialized or not created at all.

  ## Options

  All migration options are passed through to `Kirayedar.Migration.migrate/3`:
    * `:path` - Custom migrations path (defaults to priv/repo/migrations)
    * `:direction` - Migration direction, `:up` or `:down` (defaults to `:up`)
    * `:all` - Run all pending migrations (defaults to `true`)

  ## Examples

      iex> Kirayedar.create_and_migrate(MyApp.Repo, "acme_corp")
      :ok

      iex> Kirayedar.create_and_migrate(MyApp.Repo, "acme_corp",
      ...>   path: "priv/repo/tenant_migrations")
      :ok

      # If migration fails, schema is cleaned up
      iex> Kirayedar.create_and_migrate(MyApp.Repo, "bad_tenant")
      {:error, migration_error}
      # Schema "bad_tenant" does not exist

  ## Telemetry

  Emits both `:create` and `:migrate` telemetry events. If migration fails,
  also emits `:drop` event for cleanup.
  """
  @spec create_and_migrate(repo(), String.t(), keyword()) :: :ok | {:error, term()}
  def create_and_migrate(repo, tenant_id, opts \\ []) do
    with :ok <- create(repo, tenant_id) do
      case Kirayedar.Migration.migrate(repo, tenant_id, opts) do
        :ok ->
          :ok

        {:error, _} = error ->
          Logger.warning("Kirayedar: Migration failed, cleaning up schema",
            tenant: tenant_id,
            error: inspect(error)
          )

          drop(repo, tenant_id)
          error
      end
    end
  end

  # ============================================================================
  # Health Check
  # ============================================================================

  @doc """
  Verifies tenant schema exists and is accessible.

  Returns health information including whether the schema exists
  and the number of tables in the schema.

  ## Examples

      iex> Kirayedar.health_check(MyApp.Repo, "acme_corp")
      {:ok, %{schema_exists: true, tables_count: 15}}

      iex> Kirayedar.health_check(MyApp.Repo, "missing_tenant")
      {:error, :schema_not_found}

  ## Use Cases

  - Application health checks
  - Monitoring dashboards
  - Pre-flight checks before operations
  - Debugging tenant issues
  """
  @spec health_check(repo(), String.t()) :: {:ok, map()} | {:error, term()}
  def health_check(repo, tenant_id) when is_binary(tenant_id) do
    adapter = get_adapter(repo)

    case check_schema_exists(repo, adapter, tenant_id) do
      true ->
        table_count = count_tables(repo, adapter, tenant_id)
        {:ok, %{schema_exists: true, tables_count: table_count, tenant: tenant_id}}

      false ->
        {:error, :schema_not_found}
    end
  rescue
    e ->
      Logger.error("Kirayedar: Health check failed",
        tenant: tenant_id,
        error: Exception.message(e)
      )

      {:error, :health_check_failed}
  end

  # ============================================================================
  # Private Functions - Validation
  # ============================================================================

  defp validate_tenant_id(tenant_id) do
    if valid_tenant_id?(tenant_id) do
      :ok
    else
      {:error, :invalid_tenant_id}
    end
  end

  defp valid_tenant_id?(tenant_id) do
    # Only allow lowercase letters, numbers, and underscores
    # This prevents SQL injection and ensures cross-platform compatibility
    String.match?(tenant_id, ~r/^[a-z0-9_]+$/) and String.length(tenant_id) > 0
  end

  # ============================================================================
  # Private Functions - Adapter Detection
  # ============================================================================

  @doc false
  # Get adapter from the Repo module directly (safer than config)
  def get_adapter(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.MyXQL -> :mysql
      _ -> Application.get_env(:kirayedar, :adapter, :postgres)
    end
  end

  # ============================================================================
  # Private Functions - SQL Generation
  # ============================================================================

  defp create_sql(:postgres, tenant_id) do
    "CREATE SCHEMA IF NOT EXISTS \"#{tenant_id}\""
  end

  defp create_sql(:mysql, tenant_id) do
    "CREATE DATABASE IF NOT EXISTS `#{tenant_id}`"
  end

  defp drop_sql(:postgres, tenant_id) do
    "DROP SCHEMA IF EXISTS \"#{tenant_id}\" CASCADE"
  end

  defp drop_sql(:mysql, tenant_id) do
    "DROP DATABASE IF EXISTS `#{tenant_id}`"
  end

  # ============================================================================
  # Private Functions - DDL Execution
  # ============================================================================

  defp execute_ddl(repo, sql, tenant_id, operation) do
    Logger.info("Kirayedar: #{operation} tenant schema/database", tenant: tenant_id)

    case repo.query(sql) do
      {:ok, _} ->
        Logger.info("Kirayedar: Successfully #{operation}d tenant", tenant: tenant_id)
        :ok

      {:error, error} ->
        Logger.error("Kirayedar: Failed to #{operation} tenant",
          tenant: tenant_id,
          error: inspect(error)
        )

        {:error, error}
    end
  end

  # ============================================================================
  # Private Functions - Health Checks
  # ============================================================================

  defp check_schema_exists(repo, :postgres, schema) do
    {:ok, result} =
      repo.query(
        "SELECT schema_name FROM information_schema.schemata WHERE schema_name = $1",
        [schema]
      )

    result.num_rows > 0
  end

  defp check_schema_exists(repo, :mysql, database) do
    {:ok, result} =
      repo.query(
        "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?",
        [database]
      )

    result.num_rows > 0
  end

  defp count_tables(repo, :postgres, schema) do
    {:ok, result} =
      repo.query(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = $1",
        [schema]
      )

    result.rows |> List.first() |> List.first()
  end

  defp count_tables(repo, :mysql, database) do
    {:ok, result} =
      repo.query(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = ?",
        [database]
      )

    result.rows |> List.first() |> List.first()
  end

  # ============================================================================
  # Private Functions - Telemetry
  # ============================================================================

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
