defmodule Test.Support.Dogs.Store do
  use MnesiaCompanion.Store,
    table: Test.Support.Dogs.Dog,
    type: :ets
end
