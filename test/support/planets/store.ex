defmodule Test.Support.Planets.Store do
  use ActiveMemory.Store,
    table: Test.Support.Planets.Planet
end
