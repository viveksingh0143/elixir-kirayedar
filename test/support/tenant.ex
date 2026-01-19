defmodule Kirayedar.Test.Tenant do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tenants" do
    field(:name, :string)
    field(:slug, :string)
    field(:domain, :string)
    field(:status, :string, default: "active")

    timestamps()
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, [:name, :slug, :domain, :status])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> unique_constraint(:domain)
  end
end
