defmodule Test.Support.Dogs.Dog do
  use ActiveMemory.Table,
    type: :ets,
    options: [compressed: true, read_concurrency: true]

  attributes do
    field(:name, :string)
    field(:breed, :string)
    field(:weight, :integer)
    field(:dob, :string)
    field(:fixed?, :boolean, default: true)
    field(:nested, :map)
  end
end
