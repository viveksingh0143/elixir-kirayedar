import Config

config :kirayedar, ecto_repos: [Kirayedar.TestRepo]
import_config "#{config_env()}.exs"
