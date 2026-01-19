defmodule Kirayedar.Test.PostgresRepo do
  use Ecto.Repo,
    otp_app: :kirayedar,
    adapter: Ecto.Adapters.Postgres

  use Kirayedar.Repo
end

defmodule Kirayedar.Test.MySQLRepo do
  use Ecto.Repo,
    otp_app: :kirayedar,
    adapter: Ecto.Adapters.MyXQL

  use Kirayedar.Repo
end
