defmodule Test.Support.Ttl.Session do
  use ActiveMemory.Table, ttl: 50

  attributes do
    field(:name)
    field(:value)
  end
end
