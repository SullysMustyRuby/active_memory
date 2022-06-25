defmodule Test.Support.People.Store do
  use ActiveMemory.Store,
    table: Test.Support.People.Person
end
