defmodule Kirayedar.TelemetryTest do
  use ExUnit.Case, async: true

  setup context do
    on_exit(fn -> Kirayedar.put_tenant(nil) end)

    repo =
      cond do
        context[:postgres] -> Kirayedar.TestRepo.Postgres
        context[:mysql] -> Kirayedar.TestRepo.MySQL
        true -> nil
      end

    if repo do
      Ecto.Adapters.SQL.Sandbox.checkout(repo)
    end

    {:ok, repo: repo}
  end

  @tag :postgres
  test "emits [:kirayedar, :tenant, :create] event" do
    parent = self()
    handler_id = "telemetry-test"

    :telemetry.attach(
      handler_id,
      [:kirayedar, :tenant, :create],
      fn _name, _measurements, metadata, _config ->
        send(parent, {:event_captured, metadata.tenant})
      end,
      nil
    )

    # We can use a mock repo or a real one here
    Kirayedar.create(Kirayedar.TestRepo.Postgres, "telemetry_tenant")

    assert_receive {:event_captured, "telemetry_tenant"}

    :telemetry.detach(handler_id)
  end
end
