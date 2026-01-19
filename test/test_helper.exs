# Start telemetry
Application.ensure_all_started(:telemetry)

# Configure test repos
Application.put_env(:kirayedar, Kirayedar.Test.PostgresRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kirayedar_test",
  pool: Ecto.Adapters.SQL.Sandbox
)

Application.put_env(:kirayedar, Kirayedar.Test.MySQLRepo,
  username: "root",
  password: "root",
  hostname: "localhost",
  database: "kirayedar_test",
  pool: Ecto.Adapters.SQL.Sandbox
)

# Start repos
{:ok, _} = Kirayedar.Test.PostgresRepo.start_link()

# Uncomment if MySQL is available
# {:ok, _} = Kirayedar.Test.MySQLRepo.start_link()

# Set SQL Sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(Kirayedar.Test.PostgresRepo, :manual)
# Ecto.Adapters.SQL.Sandbox.mode(Kirayedar.Test.MySQLRepo, :manual)

ExUnit.start()

# Create test database schema
Kirayedar.Test.PostgresRepo.query!("""
CREATE TABLE IF NOT EXISTS tenants (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255),
  slug VARCHAR(255) UNIQUE,
  domain VARCHAR(255) UNIQUE,
  status VARCHAR(50),
  inserted_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
)
""")

# test/support/postgres_case.ex
defmodule Kirayedar.PostgresCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Kirayedar.Test.PostgresRepo, as: Repo
      import Kirayedar.PostgresCase
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Kirayedar.Test.PostgresRepo,
        shared: not tags[:async]
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end

# test/support/mysql_case.ex
defmodule Kirayedar.MySQLCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Kirayedar.Test.MySQLRepo, as: Repo
      import Kirayedar.MySQLCase
    end
  end

  setup tags do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Kirayedar.Test.MySQLRepo, shared: not tags[:async])

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
