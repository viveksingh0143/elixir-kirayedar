defmodule Kirayedar.ResolverCache do
  @moduledoc """
  Simple ETS-based cache for tenant resolution to avoid repeated database queries.
  """

  @table_name :kirayedar_resolver_cache
  # 5 minutes in milliseconds
  @ttl 300_000

  def init do
    :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
  end

  def get(host) do
    case :ets.lookup(@table_name, host) do
      [{^host, tenant_id, inserted_at}] ->
        if System.monotonic_time(:millisecond) - inserted_at < @ttl do
          {:ok, tenant_id}
        else
          :ets.delete(@table_name, host)
          :miss
        end

      [] ->
        :miss
    end
  end

  def put(host, tenant_id) do
    :ets.insert(@table_name, {host, tenant_id, System.monotonic_time(:millisecond)})
    :ok
  end

  def clear do
    :ets.delete_all_objects(@table_name)
  end
end
