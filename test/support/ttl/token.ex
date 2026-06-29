defmodule Test.Support.Ttl.Token do
  use ActiveMemory.Table, type: :ets, ttl: 50

  attributes do
    field(:name)
    field(:value)
  end
end
