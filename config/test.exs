import Config

config :kirayedar,
  admin_host: "admin.myapp.com",
  primary_domain: "myapp.com",
  tenant_model: Kirayedar.Test.Organization

config :kirayedar, Kirayedar.TestRepo.Postgres,
  database: "kirayedar_test",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :kirayedar, Kirayedar.TestRepo.MySQL,
  database: "kirayedar_test",
  username: "root",
  password: "root",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
