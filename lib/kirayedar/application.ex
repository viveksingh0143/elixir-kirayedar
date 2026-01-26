defmodule Kirayedar.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize resolver cache
    Kirayedar.ResolverCache.init()

    children = []

    opts = [strategy: :one_for_one, name: Kirayedar.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
