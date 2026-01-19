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

  @doc """
  Gets the current tenant from the process dictionary.
  """
  @spec current_tenant() :: tenant_id()
  def current_tenant do
    Process.get(@tenant_key)
  end

  @doc """
  Sets the current tenant in the process dictionary.
  When set to nil, clears the tenant context.
  """
  @spec put_tenant(tenant_id()) :: :ok
  def put_tenant(nil) do
    Process.delete(@tenant_key)
    :ok
  end

  def put_tenant(tenant_id) do
    Process.put(@tenant_key, tenant_id)
    :ok
  end

  @doc """
  Clears the current tenant from the process dictionary.
  """
  @spec clear_tenant() :: :ok
  def clear_tenant do
    Process.delete(@tenant_key)
    :ok
  end

  @doc """
  Runs a block of code without any tenant prefix.
  Useful for querying global tables from within a tenant request.

  ## Examples

      # Query global settings while in tenant context
      Kirayedar.scope_global(fn ->
        Repo.all(GlobalSettings)
      end)

      # Access shared reference data
      Kirayedar.scope_global(fn ->
        Repo.get(Country, "US")
      end)
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
  Creates a new tenant schema/database.

  ## Examples

      iex> Kirayedar.create(MyApp.Repo, "acme_corp")
      :ok

      iex> Kirayedar.create(MyApp.Repo, "invalid slug!")
      {:error, :invalid_tenant_id}
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

  ## Examples

      iex> Kirayedar.drop(MyApp.Repo, "acme_corp")
      :ok
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
  Executes a function within the context of a specific tenant.

  ## Examples

      iex> Kirayedar.with_tenant("acme_corp", fn ->
      ...>   MyApp.Repo.all(MyApp.Post)
      ...> end)
      [%MyApp.Post{}, ...]
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

  # Private Functions

  defp validate_tenant_id(tenant_id) do
    if valid_tenant_id?(tenant_id) do
      :ok
    else
      {:error, :invalid_tenant_id}
    end
  end

  defp valid_tenant_id?(tenant_id) do
    String.match?(tenant_id, ~r/^[a-z0-9_]+$/)
  end

  @doc false
  # Get adapter from the Repo module directly (safer than config)
  def get_adapter(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.MyXQL -> :mysql
      _ -> Application.get_env(:kirayedar, :adapter, :postgres)
    end
  end

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
