defmodule Kirayedar.Resolver do
  @moduledoc """
  Pure logic for identifying a tenant from a host string.

  Resolution priority:
  1. Check against admin_host configuration (returns nil)
  2. Check if entire host matches domain field in database
  3. Check if host ends with primary_domain (extracts subdomain)
  4. Fallback to first segment extraction (supports custom domains via slug)

  Automatically strips port numbers and trailing dots.
  """

  require Logger

  @type host :: String.t()
  @type tenant_id :: String.t() | nil

  @doc """
  Resolves a tenant from a host string.

  ## Examples

      iex> Kirayedar.Resolver.resolve("admin.example.com")
      nil

      iex> Kirayedar.Resolver.resolve("acme.example.com")
      "acme"

      iex> Kirayedar.Resolver.resolve("custom-domain.com")
      "acme"  # if custom-domain.com matches a tenant's domain or slug
  """
  @spec resolve(host()) :: tenant_id()
  def resolve(host) when is_binary(host) do
    host
    |> normalize_host()
    |> do_resolve()
  end

  def resolve(_), do: nil

  # Private Functions

  defp normalize_host(host) do
    host
    |> String.downcase()
    |> strip_port()
    |> String.trim_trailing(".")
  end

  defp strip_port(host) do
    case String.split(host, ":") do
      [host_without_port | _] -> host_without_port
      _ -> host
    end
  end

  defp do_resolve(host) do
    config = get_config()

    cond do
      # 1. Admin host check
      is_admin_host?(host, config) ->
        Logger.debug("Kirayedar.Resolver: Admin host detected", host: host)
        nil

      # 2. Exact domain match
      not is_nil(tenant = find_by_domain(host, config)) ->
        Logger.debug("Kirayedar.Resolver: Exact domain match", host: host, tenant: tenant)
        tenant

      # 3. Subdomain extraction
      not is_nil(tenant = extract_subdomain(host, config)) ->
        Logger.debug("Kirayedar.Resolver: Subdomain match", host: host, tenant: tenant)
        tenant

      # 4. Custom domain via slug
      not is_nil(tenant = find_by_slug(host, config)) ->
        Logger.debug("Kirayedar.Resolver: Slug match", host: host, tenant: tenant)
        tenant

      true ->
        Logger.debug("Kirayedar.Resolver: No tenant found", host: host)
        nil
    end
  end

  defp is_admin_host?(host, config) do
    admin_host = Keyword.get(config, :admin_host)
    admin_host && host == admin_host
  end

  defp find_by_domain(host, config) do
    repo = Keyword.get(config, :repo)
    tenant_model = Keyword.get(config, :tenant_model)

    cond do
      is_nil(repo) or is_nil(tenant_model) ->
        nil

      is_nil(Process.whereis(repo)) ->
        nil

      true ->
        do_find_by_domain(repo, tenant_model, host)
    end
  rescue
    Ecto.QueryError ->
      Logger.debug("Kirayedar.Resolver: Tenant table not ready", host: host)
      nil

    ArgumentError ->
      Logger.debug("Kirayedar.Resolver: Repo not available", host: host)
      nil

    e ->
      Logger.warning("Kirayedar.Resolver: Unexpected error in find_by_domain",
        error: Exception.message(e),
        host: host
      )

      nil
  end

  defp do_find_by_domain(repo, tenant_model, host) do
    case repo.get_by(tenant_model, domain: host) do
      nil -> nil
      tenant -> get_tenant_id(tenant)
    end
  end

  defp extract_subdomain(host, config) do
    primary_domain = Keyword.get(config, :primary_domain)

    if primary_domain && String.ends_with?(host, ".#{primary_domain}") do
      host
      |> String.replace_suffix(".#{primary_domain}", "")
      |> validate_subdomain()
    else
      nil
    end
  end

  defp validate_subdomain(subdomain) do
    if subdomain != "" and not String.contains?(subdomain, ".") do
      subdomain
    else
      nil
    end
  end

  defp find_by_slug(host, config) do
    first_segment = host |> String.split(".") |> List.first()

    repo = Keyword.get(config, :repo)
    tenant_model = Keyword.get(config, :tenant_model)

    cond do
      is_nil(repo) or is_nil(tenant_model) ->
        nil

      is_nil(Process.whereis(repo)) ->
        nil

      true ->
        do_find_by_slug(repo, tenant_model, first_segment)
    end
  rescue
    Ecto.QueryError ->
      Logger.debug("Kirayedar.Resolver: Tenant table not ready", host: host)
      nil

    ArgumentError ->
      Logger.debug("Kirayedar.Resolver: Repo not available", host: host)
      nil

    e ->
      Logger.warning("Kirayedar.Resolver: Unexpected error in find_by_slug",
        error: Exception.message(e),
        host: host
      )

      nil
  end

  defp do_find_by_slug(repo, tenant_model, slug) do
    case repo.get_by(tenant_model, slug: slug) do
      nil -> nil
      tenant -> get_tenant_id(tenant)
    end
  end

  defp get_tenant_id(tenant) do
    cond do
      Map.has_key?(tenant, :slug) -> tenant.slug
      Map.has_key?(tenant, :id) -> to_string(tenant.id)
      true -> nil
    end
  end

  defp get_config do
    Application.get_all_env(:kirayedar)
  end
end
