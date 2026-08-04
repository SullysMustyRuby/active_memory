defmodule Test.Support.Comets.Comet do
  use ActiveMemory.Table,
    type: :ets

  use Ecto.Schema

  embedded_schema do
    field(:name, :string)
    field(:orbit_years, :integer)
    field(:tail?, :boolean, default: true)
  end
end
