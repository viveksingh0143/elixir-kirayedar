# Kirayedar

[![Hex.pm](https://img.shields.io/hexpm/v/kirayedar.svg)](https://hex.pm/packages/kirayedar)
[![Documentation](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/kirayedar)
[![License](https://img.shields.io/hexpm/l/kirayedar.svg)](https://github.com/viveksingh0143/elixir-kirayedar/blob/main/LICENSE)

Multi-tenancy library for Elixir/Phoenix with schema-based isolation. **Kirayedar** (किरायेदार) means "tenant" in Hindi.

## Features

- 🏢 **Schema-based isolation** using PostgreSQL schemas or MySQL databases
- 🔍 **Intelligent tenant resolution** from host/subdomain/custom domains
- 🔌 **Plug integration** for automatic tenant context in Phoenix
- 📊 **Migration helpers** for running migrations across all tenants
- 📈 **Telemetry support** for monitoring and observability
- 🪶 **Lightweight** with minimal dependencies
- 📝 **Observable** with comprehensive structured logging
- 🔄 **Dynamic adapter detection** from your Repo configuration
- 🛠️ **Mix tasks** for easy setup and code generation
- 💚 **Health checks** for monitoring tenant status
- ⚡ **Atomic operations** with create-and-migrate functionality

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Usage](#usage)
  - [Basic Operations](#basic-operations)
  - [Tenant Context Management](#tenant-context-management)
  - [Migrations](#migrations)
  - [Health Checks](#health-checks)
- [Phoenix Integration](#phoenix-integration)
- [Advanced Usage](#advanced-usage)
  - [Background Jobs](#background-jobs)
  - [Multi-Tenant Testing](#multi-tenant-testing)
  - [Global vs Tenant Scope](#global-vs-tenant-scope)
  - [Custom Domains](#custom-domains)
- [Production Deployment](#production-deployment)
- [Monitoring & Telemetry](#monitoring--telemetry)
- [Testing](#testing)
- [API Reference](#api-reference)
- [Mix Tasks](#mix-tasks)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add `kirayedar` to your list of dependencies in `mix.exs`:
```elixir
def deps do
  [
    {:kirayedar, "~> 0.1.0"},
    # Choose your database adapter
    {:postgrex, ">= 0.0.0"},  # For PostgreSQL
    # {:myxql, ">= 0.0.0"},   # For MySQL
  ]
end
```

Then run:
```bash
mix deps.get
```

## Quick Start

### Option 1: Interactive Setup (Recommended)

Run the interactive setup task:
```bash
mix kirayedar.setup
```

This will:
- Prompt you for configuration options
- Generate the tenant model
- Create the tenant table migration
- Update your `config/config.exs`
- Optionally generate LiveView CRUD interfaces

**Example session:**
```
╔═══════════════════════════════════════╗
║   Kirayedar Multi-Tenancy Setup       ║
╚═══════════════════════════════════════╝

What do you want to call your tenant/organization? [Tenant]: Organization
Do you want to use binary_id (UUID)? [Yn]: Y
What is your Admin Host? [localhost]: admin.myapp.com
What is your primary domain? [example.com]: myapp.com
Do you want to generate LiveViews for CRUD? [Yn]: Y

✔ Kirayedar Setup Complete!
```

### Option 2: Manual Setup

1. **Configure Kirayedar** in `config/config.exs`:
```elixir
config :kirayedar,
  repo: MyApp.Repo,
  primary_domain: "myapp.com",
  admin_host: "admin.myapp.com",
  tenant_model: MyApp.Accounts.Organization
```

2. **Create your tenant model**:
```elixir
defmodule MyApp.Accounts.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :domain, :string
    field :status, :string, default: "active"
    field :settings, :map, default: %{}

    timestamps()
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name, :slug, :domain, :status, :settings])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9_]+$/)
    |> unique_constraint(:slug)
    |> unique_constraint(:domain)
  end
end
```

3. **Create migration**:
```bash
mix ecto.gen.migration create_organizations
```
```elixir
defmodule MyApp.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :domain, :string
      add :status, :string, default: "active", null: false
      add :settings, :map, default: "{}", null: false

      timestamps()
    end

    create unique_index(:organizations, [:slug])
    create unique_index(:organizations, [:domain])
    create index(:organizations, [:status])
  end
end
```

### Complete the Setup

1. **Update your Repo** (`lib/my_app/repo.ex`):
```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  # Add this line
  use Kirayedar.Repo
end
```

2. **Add the Plug to your Endpoint** (`lib/my_app_web/endpoint.ex`):
```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # Add before your router plug
  plug Kirayedar.Plug

  # ... rest of your plugs
  plug MyAppWeb.Router
end
```

3. **Run migrations**:
```bash
mix ecto.migrate
```

4. **Create your first tenant**:
```elixir
# In IEx or a seed file
iex> alias MyApp.{Repo, Accounts.Organization}

# Create the organization record
iex> org = %Organization{name: "Acme Corp", slug: "acme_corp"} 
     |> Organization.changeset(%{})
     |> Repo.insert!()

# Create the schema and run migrations
iex> Kirayedar.create_and_migrate(Repo, org.slug)
:ok
```

## Configuration

### Basic Configuration
```elixir
# config/config.exs
config :kirayedar,
  repo: MyApp.Repo,                          # Your Ecto Repo
  primary_domain: "myapp.com",               # Your primary domain
  admin_host: "admin.myapp.com",             # Admin subdomain (returns nil tenant)
  tenant_model: MyApp.Accounts.Organization, # Your tenant model
  adapter: :postgres                         # Optional: :postgres or :mysql
```

### Environment-Specific Configuration
```elixir
# config/dev.exs
config :kirayedar,
  primary_domain: "lvh.me",  # Use lvh.me for local development
  admin_host: "admin.lvh.me"

# config/prod.exs
config :kirayedar,
  primary_domain: "myapp.com",
  admin_host: "admin.myapp.com"
```

### Custom Plug Options
```elixir
# In your endpoint or router
plug Kirayedar.Plug, assign_key: :current_organization
```

## Usage

### Basic Operations

#### Creating a Tenant
```elixir
# Simple creation (schema only)
Kirayedar.create(MyApp.Repo, "acme_corp")
# => :ok

# Atomic creation with migrations (recommended)
Kirayedar.create_and_migrate(MyApp.Repo, "acme_corp")
# => :ok
# If migration fails, schema is automatically cleaned up

# With custom migration path
Kirayedar.create_and_migrate(
  MyApp.Repo, 
  "acme_corp",
  path: "priv/repo/tenant_migrations"
)
```

#### Dropping a Tenant
```elixir
# ⚠️ Warning: This permanently deletes all tenant data!
Kirayedar.drop(MyApp.Repo, "acme_corp")
# => :ok
```

#### Health Check
```elixir
# Check if tenant exists and get info
Kirayedar.health_check(MyApp.Repo, "acme_corp")
# => {:ok, %{schema_exists: true, tables_count: 15, tenant: "acme_corp"}}

Kirayedar.health_check(MyApp.Repo, "nonexistent")
# => {:error, :schema_not_found}
```

### Tenant Context Management

#### Setting Current Tenant
```elixir
# Set tenant for current process
Kirayedar.put_tenant("acme_corp")

# All queries now use acme_corp schema
Repo.all(Post)  # Queries acme_corp.posts

# Get current tenant
Kirayedar.current_tenant()
# => "acme_corp"

# Clear tenant
Kirayedar.clear_tenant()
```

#### Scoped Execution
```elixir
# Execute in specific tenant context
posts = Kirayedar.with_tenant("acme_corp", fn ->
  Repo.all(Post)
end)

# Execute without tenant (global scope)
settings = Kirayedar.scope_global(fn ->
  Repo.all(GlobalSettings)
end)

# Nested scopes work correctly
Kirayedar.with_tenant("tenant_a", fn ->
  # Working in tenant_a
  
  Kirayedar.with_tenant("tenant_b", fn ->
    # Temporarily in tenant_b
  end)
  
  # Back to tenant_a
end)
```

### Migrations

#### Migrate Specific Tenant
```elixir
# Run all pending migrations
Kirayedar.Migration.migrate(MyApp.Repo, "acme_corp")

# With custom path
Kirayedar.Migration.migrate(
  MyApp.Repo,
  "acme_corp",
  path: "priv/repo/tenant_migrations"
)

# Run specific number of migrations
Kirayedar.Migration.migrate(
  MyApp.Repo,
  "acme_corp",
  all: false,
  step: 1
)
```

#### Migrate All Tenants
```elixir
# Migrate all tenants at once
Kirayedar.Migration.migrate_all(
  MyApp.Repo,
  MyApp.Accounts.Organization
)

# With custom path
Kirayedar.Migration.migrate_all(
  MyApp.Repo,
  MyApp.Accounts.Organization,
  path: "priv/repo/tenant_migrations"
)
```

#### Rollback Migrations
```elixir
# Rollback last migration
Kirayedar.Migration.rollback(MyApp.Repo, "acme_corp")

# Rollback multiple steps
Kirayedar.Migration.rollback(MyApp.Repo, "acme_corp", step: 3)

# With custom path
Kirayedar.Migration.rollback(
  MyApp.Repo,
  "acme_corp",
  path: "priv/repo/tenant_migrations",
  step: 1
)
```

### Health Checks
```elixir
# Single tenant
case Kirayedar.health_check(MyApp.Repo, "acme_corp") do
  {:ok, %{schema_exists: true, tables_count: count}} ->
    Logger.info("Tenant healthy with #{count} tables")
  {:error, :schema_not_found} ->
    Logger.error("Tenant schema missing!")
end

# Check all tenants
defmodule MyApp.HealthCheck do
  def check_all_tenants do
    MyApp.Repo.all(MyApp.Accounts.Organization)
    |> Enum.map(fn org ->
      {org.slug, Kirayedar.health_check(MyApp.Repo, org.slug)}
    end)
  end
end
```

## Phoenix Integration

### Automatic Tenant Resolution

The `Kirayedar.Plug` automatically resolves tenants from the request:
```elixir
# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  plug Kirayedar.Plug  # Add before router

  plug MyAppWeb.Router
end
```

**Resolution Priority:**

1. **Admin host** → returns `nil` (for admin.myapp.com)
2. **Exact domain match** → checks `domain` field in database
3. **Subdomain extraction** → extracts from primary domain
4. **Slug fallback** → checks `slug` field for custom domains

**Examples:**
```
admin.myapp.com        → nil (admin access)
acme.myapp.com         → "acme" (subdomain)
acme.myapp.com:4000    → "acme" (port stripped)
custom-domain.com      → "acme" (if domain matches in DB)
```

### Using in Controllers
```elixir
defmodule MyAppWeb.PostController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    # Tenant is already set by the Plug
    tenant = conn.assigns.tenant
    posts = MyApp.Blog.list_posts()  # Automatically scoped to tenant
    
    render(conn, "index.html", posts: posts, tenant: tenant)
  end
end
```

### Using in LiveView
```elixir
defmodule MyAppWeb.PostLive.Index do
  use MyAppWeb, :live_view

  def mount(_params, _session, socket) do
    # Tenant is in socket assigns
    tenant = socket.assigns.tenant
    
    {:ok, 
     socket
     |> assign(:tenant, tenant)
     |> stream(:posts, MyApp.Blog.list_posts())}
  end
end
```

### Admin Routes
```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  # Admin pipeline - no tenant required
  pipeline :admin do
    plug :browser
    plug :require_admin
  end

  # Tenant pipeline - tenant required
  pipeline :tenant do
    plug :browser
    plug :require_tenant
  end

  scope "/admin", MyAppWeb.Admin do
    pipe_through :admin
    
    resources "/organizations", OrganizationController
  end

  scope "/", MyAppWeb do
    pipe_through :tenant
    
    live "/dashboard", DashboardLive
    resources "/posts", PostController
  end

  # Helper plugs
  defp require_admin(conn, _opts) do
    if is_nil(conn.assigns.tenant) do
      conn
    else
      conn
      |> put_flash(:error, "Admin access only")
      |> redirect(to: "/")
      |> halt()
    end
  end

  defp require_tenant(conn, _opts) do
    if conn.assigns.tenant do
      conn
    else
      conn
      |> put_flash(:error, "Tenant required")
      |> redirect(to: "/")
      |> halt()
    end
  end
end
```

## Advanced Usage

### Background Jobs

#### With Oban
```elixir
defmodule MyApp.Workers.ReportWorker do
  use Oban.Worker, queue: :reports

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tenant_id" => tenant_id, "report_type" => type}}) do
    Kirayedar.with_tenant(tenant_id, fn ->
      MyApp.Reports.generate(type)
    end)
  end
end

# Enqueue job
%{tenant_id: "acme_corp", report_type: "monthly"}
|> MyApp.Workers.ReportWorker.new()
|> Oban.insert()
```

#### With Quantum
```elixir
defmodule MyApp.Scheduler do
  use Quantum, otp_app: :my_app

  def process_all_tenants do
    MyApp.Repo.all(MyApp.Accounts.Organization)
    |> Enum.each(fn org ->
      Kirayedar.with_tenant(org.slug, fn ->
        MyApp.DailyProcessing.run()
      end)
    end)
  end
end

# config/config.exs
config :my_app, MyApp.Scheduler,
  jobs: [
    {"0 2 * * *", {MyApp.Scheduler, :process_all_tenants, []}}
  ]
```

### Multi-Tenant Testing
```elixir
defmodule MyApp.Blog.PostTest do
  use MyApp.DataCase

  alias MyApp.Blog.Post

  setup do
    # Create test tenant
    tenant_slug = "test_tenant_#{System.unique_integer([:positive])}"
    Kirayedar.create(Repo, tenant_slug)
    Kirayedar.put_tenant(tenant_slug)

    on_exit(fn ->
      Kirayedar.clear_tenant()
      Kirayedar.drop(Repo, tenant_slug)
    end)

    {:ok, tenant: tenant_slug}
  end

  test "creates post in tenant scope" do
    attrs = %{title: "Test Post", body: "Content"}
    {:ok, post} = MyApp.Blog.create_post(attrs)
    
    assert post.title == "Test Post"
  end

  test "tenant isolation works", %{tenant: tenant} do
    # Create data in current tenant
    MyApp.Blog.create_post(%{title: "Tenant 1 Post"})

    # Create another tenant
    other_tenant = "other_#{System.unique_integer([:positive])}"
    Kirayedar.create(Repo, other_tenant)

    # Switch to other tenant
    count = Kirayedar.with_tenant(other_tenant, fn ->
      Repo.aggregate(Post, :count)
    end)

    assert count == 0  # Data is isolated

    # Cleanup
    Kirayedar.drop(Repo, other_tenant)
  end
end
```

### Global vs Tenant Scope
```elixir
defmodule MyApp.Settings do
  # Get tenant-specific setting
  def get_tenant_setting(key) do
    Repo.get_by(Setting, key: key)
  end

  # Get global setting (shared across all tenants)
  def get_global_setting(key) do
    Kirayedar.scope_global(fn ->
      Repo.get_by(GlobalSetting, key: key)
    end)
  end

  # Mixed operation
  def get_effective_setting(key) do
    # Try tenant-specific first
    case get_tenant_setting(key) do
      nil -> get_global_setting(key)  # Fallback to global
      setting -> setting
    end
  end
end
```

### Custom Domains
```elixir
# Create organization with custom domain
org = %Organization{
  name: "Acme Corp",
  slug: "acme_corp",
  domain: "acme.example.com"  # Custom domain
}
|> Repo.insert!()

# Now these all resolve to the same tenant:
# - acme_corp.myapp.com (subdomain)
# - acme.example.com (custom domain)
```

## Production Deployment

### Release Tasks
```elixir
# lib/my_app/release.ex
defmodule MyApp.Release do
  @moduledoc """
  Release tasks for production deployment.
  """

  @app :my_app

  def migrate do
    load_app()

    # Migrate global tables first
    {:ok, _, _} = Ecto.Migrator.with_repo(MyApp.Repo, &Ecto.Migrator.run(&1, :up, all: true))

    # Then migrate all tenants
    migrate_tenants()
  end

  def migrate_tenants do
    load_app()

    {:ok, _, _} = Ecto.Migrator.with_repo(MyApp.Repo, fn _repo ->
      Kirayedar.Migration.migrate_all(
        MyApp.Repo,
        MyApp.Accounts.Organization
      )
    end)
  end

  def rollback(version) do
    load_app()

    {:ok, _, _} = Ecto.Migrator.with_repo(MyApp.Repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp load_app do
    Application.load(@app)
  end
end
```

### Using Release Tasks
```bash
# In production (after deployment)
/app/bin/my_app eval "MyApp.Release.migrate()"

# Or with mix in development
mix run -e "MyApp.Release.migrate()"
```

### Connection Pooling
```elixir
# config/prod.exs
config :my_app, MyApp.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
  queue_target: 5000,
  queue_interval: 1000
```

**Sizing Guidelines:**
- **Small app** (< 10 tenants): pool_size: 10-15
- **Medium app** (10-50 tenants): pool_size: 20-30
- **Large app** (50+ tenants): pool_size: 30-50

### Database Backups

#### PostgreSQL
```bash
# Backup all schemas (including tenants)
pg_dump -U postgres -d myapp_prod > full_backup.sql

# Backup specific tenant
pg_dump -U postgres -d myapp_prod -n acme_corp > acme_corp_backup.sql

# Backup all tenant schemas (pattern matching)
pg_dump -U postgres -d myapp_prod -n "tenant_*" > all_tenants_backup.sql

# Restore specific tenant
psql -U postgres -d myapp_prod < acme_corp_backup.sql
```

#### MySQL
```bash
# Backup all databases
mysqldump -u root -p --all-databases > full_backup.sql

# Backup specific tenant database
mysqldump -u root -p acme_corp > acme_corp_backup.sql

# Restore specific tenant
mysql -u root -p acme_corp < acme_corp_backup.sql
```

## Monitoring & Telemetry

### Setting Up Telemetry
```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  def start(_type, _args) do
    # Attach telemetry handlers
    :telemetry.attach_many(
      "kirayedar-handler",
      [
        [:kirayedar, :tenant, :create],
        [:kirayedar, :tenant, :drop],
        [:kirayedar, :tenant, :migrate],
        [:kirayedar, :tenant, :create, :error],
        [:kirayedar, :tenant, :drop, :error],
        [:kirayedar, :tenant, :migrate, :error]
      ],
      &MyApp.TelemetryHandler.handle_event/4,
      nil
    )

    # ... rest of supervision tree
  end
end
```

### Telemetry Handler
```elixir
defmodule MyApp.TelemetryHandler do
  require Logger

  def handle_event([:kirayedar, :tenant, action], measurements, metadata, _config) do
    Logger.info("Tenant operation completed",
      action: action,
      tenant: metadata.tenant,
      duration_ms: measurements.duration
    )

    # Send to your monitoring service
    MyApp.Metrics.record_tenant_operation(action, measurements.duration)
  end

  def handle_event([:kirayedar, :tenant, action, :error], _measurements, metadata, _config) do
    Logger.error("Tenant operation failed",
      action: action,
      tenant: metadata.tenant,
      error: inspect(metadata.error)
    )

    # Alert on failures
    MyApp.Alerts.send_alert(:tenant_operation_failed, metadata)
  end
end
```

### Metrics with Telemetry.Metrics
```elixir
# lib/my_app_web/telemetry.ex
defmodule MyAppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Tenant Operations
      counter("kirayedar.tenant.create.count"),
      counter("kirayedar.tenant.drop.count"),
      counter("kirayedar.tenant.migrate.count"),
      distribution("kirayedar.tenant.create.duration", unit: {:native, :millisecond}),
      distribution("kirayedar.tenant.migrate.duration", unit: {:native, :millisecond}),

      # Errors
      counter("kirayedar.tenant.create.error.count"),
      counter("kirayedar.tenant.drop.error.count"),
      counter("kirayedar.tenant.migrate.error.count")
    ]
  end

  defp periodic_measurements do
    [
      {MyApp.Metrics, :measure_tenant_count, []}
    ]
  end
end
```

### Health Check Endpoint
```elixir
# lib/my_app_web/controllers/health_controller.ex
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def show(conn, _params) do
    health_status = check_tenants()

    status = if Enum.all?(health_status, fn {_, status} -> status == :ok end) do
      :ok
    else
      :degraded
    end

    conn
    |> put_status(if status == :ok, do: 200, else: 503)
    |> json(%{
      status: status,
      tenants: health_status,
      timestamp: DateTime.utc_now()
    })
  end

  defp check_tenants do
    MyApp.Repo.all(MyApp.Accounts.Organization)
    |> Enum.map(fn org ->
      case Kirayedar.health_check(MyApp.Repo, org.slug) do
        {:ok, _} -> {org.slug, :ok}
        {:error, _} -> {org.slug, :error}
      end
    end)
  end
end
```

## Testing

### Running Tests
```bash
# Run all tests
mix test

# Run PostgreSQL tests only
mix test test/kirayedar_postgres_test.exs

# Run with coverage
mix test --cover

# Run specific test
mix test test/kirayedar/migration_test.exs:42
```

### Test Database Setup

#### PostgreSQL
```bash
# Create test database
createdb kirayedar_test

# Or using psql
psql -U postgres -c "CREATE DATABASE kirayedar_test;"
```

#### MySQL
```bash
# Create test database
mysql -u root -p -e "CREATE DATABASE kirayedar_test;"
```

### Test Configuration
```elixir
# config/test.exs
import Config

config :kirayedar,
  admin_host: "admin.test.local",
  primary_domain: "test.local",
  tenant_model: Kirayedar.Test.Tenant

config :kirayedar, Kirayedar.Test.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kirayedar_test",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
```

### Writing Tests
```elixir
defmodule MyApp.TenantIsolationTest do
  use MyApp.DataCase

  test "data is isolated between tenants" do
    # Create two tenants
    Kirayedar.create(Repo, "tenant_a")
    Kirayedar.create(Repo, "tenant_b")

    # Insert data in tenant_a
    Kirayedar.with_tenant("tenant_a", fn ->
      %Post{title: "Tenant A Post"} |> Repo.insert!()
    end)

    # Verify tenant_b doesn't see it
    count = Kirayedar.with_tenant("tenant_b", fn ->
      Repo.aggregate(Post, :count)
    end)

    assert count == 0

    # Cleanup
    Kirayedar.drop(Repo, "tenant_a")
    Kirayedar.drop(Repo, "tenant_b")
  end
end
```

## API Reference

### Core Functions

| Function | Description |
|----------|-------------|
| `current_tenant/0` | Get current tenant ID |
| `put_tenant/1` | Set current tenant ID |
| `clear_tenant/0` | Clear current tenant |
| `with_tenant/2` | Execute function in tenant scope |
| `scope_global/1` | Execute function without tenant scope |
| `create/2` | Create tenant schema |
| `drop/2` | Drop tenant schema |
| `create_and_migrate/3` | Atomically create and migrate tenant |
| `health_check/2` | Check tenant health status |

### Migration Functions

| Function | Description |
|----------|-------------|
| `Migration.migrate/3` | Run migrations for specific tenant |
| `Migration.migrate_all/3` | Run migrations for all tenants |
| `Migration.rollback/3` | Rollback migrations for tenant |

### Resolver Functions

| Function | Description |
|----------|-------------|
| `Resolver.resolve/1` | Resolve tenant from host |

## Mix Tasks

### `mix kirayedar.setup`

Interactive setup wizard.

**Generates:**
- Tenant model
- Migration file
- Configuration updates
- Optional LiveView CRUD

**Usage:**
```bash
mix kirayedar.setup
```

### `mix kirayedar.gen.live`

Generates LiveView CRUD for tenant management.

**Generates:**
- Index LiveView
- Form component
- Show LiveView

**Usage:**
```bash
mix kirayedar.gen.live
```

**Requires:** Prior `mix kirayedar.setup`

## Troubleshooting

### Common Issues

#### Tenant not being set

**Problem:** Queries run against public schema instead of tenant schema.

**Solution:**
```elixir
# Check if Kirayedar.Plug is added to endpoint
# lib/my_app_web/endpoint.ex
plug Kirayedar.Plug  # Must be before Router

# Verify Repo has Kirayedar.Repo
# lib/my_app/repo.ex
use Kirayedar.Repo
```

#### Migration fails for some tenants

**Problem:** `migrate_all` fails partway through.

**Solution:**
```elixir
# Use create_and_migrate for atomic operations
Kirayedar.create_and_migrate(Repo, tenant_id)

# Check migration errors
case Kirayedar.Migration.migrate_all(Repo, Tenant) do
  :ok -> :ok
  {:error, failures} ->
    # Log
