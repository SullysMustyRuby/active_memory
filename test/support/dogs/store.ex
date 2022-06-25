defmodule Test.Support.Dogs.Store do
  use ActiveMemory.Store,
    table: Test.Support.Dogs.Dog,
    type: :ets
end
