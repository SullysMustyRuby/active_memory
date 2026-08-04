defmodule Test.Support.Planets.Planet do
  use ActiveMemory.Table,
    type: :ets

  attributes auto_generate_uuid: true do
    field(:name, :string)
    field(:gravity, :float)
    field(:moons, :integer, default: 0)
    field(:atmosphere)
  end
end
