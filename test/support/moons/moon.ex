defmodule Test.Support.Moons.Moon do
  use ActiveMemory.Table

  use Ecto.Schema

  @primary_key false
  embedded_schema do
    field(:name, :string)
    field(:planet, :string)
    field(:radius_km, :float)
  end
end
