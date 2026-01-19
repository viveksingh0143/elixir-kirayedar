# Kirayedar

Multi-tenancy library for Elixir/Phoenix with schema-based isolation.

## Features

- 🏢 **Schema-based isolation** using PostgreSQL schemas or MySQL databases
- 🔍 **Intelligent tenant resolution** from host/subdomain
- 🔌 **Plug integration** for automatic tenant context
- 📊 **Migration helpers** for multi-tenant databases
- 📈 **Telemetry support** for monitoring and observability
- 🪶 **Lightweight** with minimal dependencies
- 📝 **Observable** with comprehensive structured logging
- 🔄 **Dynamic adapter detection** from your Repo configuration
- 🛠️ **Mix tasks** for easy setup and code generation

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

## Quick Start with Mix Tasks

### 1. Setup Kirayedar

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

Example session:
```
What do you want to call your tenant/organization? [Tenant]: Organization
Do you want to use binary_id (UUID)? [Yn]: Y
What is your Admin Host? [localhost]: admin.myapp.com
What is your primary domain? [example.com]: myapp.com
Do you want to generate LiveViews for CRUD? [Yn]: Y
```

### 2. Run Migrations

```bash
mix ecto.migrate
```

### 3. Add Plug to Your Endpoint

Edit `lib/my_app_web/endpoint.ex`:

```elixir
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  # Add this line
  plug Kirayedar.Plug

  # ... rest of your plugs
end
```

### 4. Update Your Repo

Edit `lib/my_app/repo.ex`:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  # Add this line
  use Kirayedar.Repo
end
```

### 5. Create Your First Tenant

```elixir
iex> Kirayedar.create(MyApp.Repo, "acme_corp")
:ok

iex> Kirayedar.Migration.migrate(MyApp.Repo, "acme_corp")
:ok
```

## Manual Configuration

If you prefer manual setup, configure in `config/config.exs`:

```elixir
config :kirayedar,
  repo: MyApp.Repo,
  primary_domain: "example.com",
  admin_host: "admin.example.com",
  tenant_model: MyApp.Accounts.Organization
  # adapter: :postgres  # Optional - auto-detected from Repo
```

## Usage

### Creating and Managing Tenants

```elixir
# Create a tenant schema
Kirayedar.create(MyApp.Repo, "acme_corp")

# Run migrations for the tenant
Kirayedar.Migration.migrate(MyApp.Repo, "acme_corp")

# Drop a tenant schema
Kirayedar.drop(MyApp.Repo, "acme_corp")

# Rollback migrations
Kirayedar.Migration.rollback(MyApp.Repo, "acme_corp", step: 1)
```

### Migrating All Tenants

```elixir
# In your release tasks or deployment scripts
defmodule MyApp.ReleaseTasks do
  def migrate_all do
    {:ok, _} = Application.ensure_all_started(:kirayedar)
    
    Kirayedar.Migration.migrate_all(
      MyApp.Repo,
      MyApp.Accounts.Organization
    )
  end
end
```

### Global Scope

Query global tables while in a tenant context:

```elixir
# Inside a tenant request
Kirayedar.scope_global(fn ->
  Repo.all(GlobalSettings)
end)
```

### Manual Tenant Context

```elixir
# Set tenant manually
Kirayedar.put_tenant("acme_corp")
Repo.all(Post)  # Queries acme_corp schema

# Execute in specific tenant context
Kirayedar.with_tenant("acme_corp", fn ->
  Repo.all(Post)
end)
```

## Telemetry Integration

Monitor tenant operations with Telemetry:

```elixir
# In your application.ex
defmodule MyApp.Application do
  def start(_type, _args) do
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

    # ... rest of your supervision tree
  end
end

defmodule MyApp.TelemetryHandler do
  require Logger

  def handle_event([:kirayedar, :tenant, action], measurements, metadata, _config) do
    Logger.info("Tenant operation completed",
      action: action,
      tenant: metadata.tenant,
      duration_ms: measurements.duration
    )
  end

  def handle_event([:kirayedar, :tenant, action, :error], _measurements, metadata, _config) do
    Logger.error("Tenant operation failed",
      action: action,
      tenant: metadata.tenant,
      error: inspect(metadata.error)
    )
  end
end
```

## Tenant Resolution

Kirayedar resolves tenants in the following priority order:

1. **Admin host check** - Returns `nil` for admin domain
2. **Exact domain match** - Checks `domain` field in tenant model
3. **Subdomain extraction** - Extracts subdomain from primary domain
4. **Slug fallback** - Checks `slug` field for custom domains

Examples:
```
admin.example.com       → nil (admin host)
acme.example.com        → "acme" (subdomain)
custom-domain.com       → looks up by domain/slug in DB
acme.example.com:4000   → "acme" (port stripped)
```

## Testing

### Running Tests

```bash
# Run all tests
mix test

# Run PostgreSQL tests only
mix test test/kirayedar_postgres_test.exs

# Run MySQL tests only (requires MySQL)
mix test test/kirayedar_mysql_test.exs

# Run with coverage
mix test --cover
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

Update `config/test.exs`:

```elixir
# PostgreSQL
config :kirayedar, Kirayedar.Test.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kirayedar_test",
  pool: Ecto.Adapters.SQL.Sandbox

# MySQL (optional)
config :kirayedar, Kirayedar.Test.MySQLRepo,
  username: "root",
  password: "root",
  hostname: "localhost",
  database: "kirayedar_test",
  pool: Ecto.Adapters.SQL.Sandbox
```

### Writing Tests

```elixir
defmodule MyApp.TenantTest do
  use MyApp.DataCase

  test "tenant isolation works" do
    Kirayedar.create(Repo, "tenant1")
    Kirayedar.create(Repo, "tenant2")

    # Insert data in tenant1
    Kirayedar.with_tenant("tenant1", fn ->
      %Post{title: "Tenant 1 Post"} |> Repo.insert!()
    end)

    # Verify isolation
    count = Kirayedar.with_tenant("tenant2", fn ->
      Repo.aggregate(Post, :count)
    end)

    assert count == 0
  end
end
```

## Mix Tasks Reference

### `mix kirayedar.setup`

Interactive setup wizard that generates:
- Tenant model with customizable name
- Migration file
- Configuration updates
- Optional LiveView CRUD

### `mix kirayedar.gen.live`

Generates LiveView components for tenant management:
- Index view with listing
- Form component for create/update
- Show view for details

Requires prior `mix kirayedar.setup`.

## Production Considerations

### 1. Connection Pooling

Each tenant schema uses the same connection pool, but queries include the prefix. Monitor your pool size:

```elixir
config :my_app, MyApp.Repo,
  pool_size: 20,  # Adjust based on tenant count and load
  queue_target: 5000
```

### 2. Migration Strategy

For production deployments:

```elixir
# In your release module
def migrate do
  # Migrate global tables first
  Ecto.Migrator.run(MyApp.Repo, :up, all: true)
  
  # Then migrate all tenants
  Kirayedar.Migration.migrate_all(MyApp.Repo, MyApp.Accounts.Organization)
end
```

### 3. Monitoring

Use telemetry to track:
- Migration durations
- Tenant creation/deletion
- Schema switching overhead
- Failed operations

### 4. Backup Strategy

For PostgreSQL:
```bash
# Backup all schemas
pg_dump -U postgres -d myapp_db -n "tenant_*" > tenant_backups.sql

# Backup specific tenant
pg_dump -U postgres -d myapp_db -n "acme_corp" > acme_corp_backup.sql
```

For MySQL:
```bash
# Backup specific tenant database
mysqldump -u root -p acme_corp > acme_corp_backup.sql
```

## Structured Logging

Kirayedar uses structured logging with keyword lists:

```elixir
# Logs appear as:
[info] Kirayedar: create tenant schema/database tenant=acme_corp
[info] Kirayedar.Resolver: Subdomain match host=acme.example.com tenant=acme
[info] Kirayedar.Migration: Running migrations tenant=acme_corp duration_ms=1234
```

Works seamlessly with:
- Datadog
- CloudWatch
- Loki
- ElasticSearch

## License

Apache 2.0

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests (`mix test`)
4. Commit your changes (`git commit -am 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## Support

- GitHub Issues: https://github.com/viveksingh0143/elixir-kirayedar/issues
- Documentation: https://hexdocs.pm/kirayedar
