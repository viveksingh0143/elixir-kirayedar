import Config

config :kirayedar,
  admin_host: "admin.myapp.com",
  primary_domain: "myapp.com",
  tenant_model: Kirayedar.Test.Tenant

config :kirayedar, Kirayedar.Test.PostgresRepo,
  database: "kirayedar_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  priv: "test/support"

config :kirayedar, Kirayedar.Test.MySQLRepo,
  database: "kirayedar_test",
  username: "root",
  password: "root",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  priv: "test/support"
