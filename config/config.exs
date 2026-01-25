import Config

config :kirayedar,
  ecto_repos: [
    Kirayedar.Test.PostgresRepo,
    Kirayedar.Test.MySQLRepo
  ]

import_config "#{config_env()}.exs"
