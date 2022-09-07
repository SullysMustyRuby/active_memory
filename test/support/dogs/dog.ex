defmodule Test.Support.Dogs.Dog do
  use ActiveMemory.Table,
    type: :ets,
    options: [compressed: true, read_concurrency: true]

  attributes do
    field(:name)
    field(:breed)
    field(:weight)
    field(:dob)
    field(:fixed?, default: true)
    field(:nested)
  end
end
