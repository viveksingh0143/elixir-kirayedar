defmodule Kirayedar.ResolverCache do
  @moduledoc """
  Simple ETS-based cache for tenant resolution to avoid repeated database queries.

  The cache stores host-to-tenant_id mappings with a configurable TTL.

  ## Configuration

  The default TTL is 5 minutes (300,000 milliseconds). You can configure it:

      config :kirayedar, :resolver_cache_ttl, 300_000  # 5 minutes

  ## Usage

      # Initialize the cache (typically done in application start)
      Kirayedar.ResolverCache.init()

      # Get a cached value
      case Kirayedar.ResolverCache.get("acme.example.com") do
        {:ok, tenant_id} -> tenant_id
        :miss -> # Perform lookup and cache result
      end

      # Store a value
      Kirayedar.ResolverCache.put("acme.example.com", "acme")

      # Clear all cache entries
      Kirayedar.ResolverCache.clear()
  """

  @table_name :kirayedar_resolver_cache
  # 5 minutes in milliseconds
  @default_ttl 300_000

  @doc """
  Initializes the ETS cache table.

  Should be called once during application startup.
  Safe to call multiple times (will raise if table exists).

  ## Examples

      iex> Kirayedar.ResolverCache.init()
      :kirayedar_resolver_cache
  """
  def init do
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
  end

  @doc """
  Retrieves a cached tenant_id for the given host.

  Returns `{:ok, tenant_id}` if found and not expired.
  Returns `:miss` if not found or expired.

  Expired entries are automatically deleted.

  ## Examples

      iex> Kirayedar.ResolverCache.get("acme.example.com")
      {:ok, "acme"}

      iex> Kirayedar.ResolverCache.get("unknown.example.com")
      :miss
  """
  def get(host) do
    case :ets.lookup(@table_name, host) do
      [{^host, tenant_id, inserted_at}] ->
        if fresh?(inserted_at) do
          {:ok, tenant_id}
        else
          :ets.delete(@table_name, host)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError ->
      # Table doesn't exist yet
      :miss
  end

  @doc """
  Stores a tenant_id for the given host with current timestamp.

  ## Examples

      iex> Kirayedar.ResolverCache.put("acme.example.com", "acme")
      :ok

      iex> Kirayedar.ResolverCache.put("admin.example.com", nil)
      :ok
  """
  def put(host, tenant_id) do
    :ets.insert(@table_name, {host, tenant_id, System.monotonic_time(:millisecond)})
    :ok
  rescue
    ArgumentError ->
      # Table doesn't exist - initialize and retry
      init()
      :ets.insert(@table_name, {host, tenant_id, System.monotonic_time(:millisecond)})
      :ok
  end

  @doc """
  Clears all entries from the cache.

  ## Examples

      iex> Kirayedar.ResolverCache.clear()
      :ok
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  rescue
    ArgumentError ->
      # Table doesn't exist
      :ok
  end

  # Private Functions

  defp fresh?(inserted_at) do
    ttl = Application.get_env(:kirayedar, :resolver_cache_ttl, @default_ttl)
    System.monotonic_time(:millisecond) - inserted_at < ttl
  end
end
