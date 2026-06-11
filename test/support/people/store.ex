defmodule Test.Support.People.Store do
  use ActiveMemory.Store,
    table: Test.Support.People.Person,
    seed_file: Path.expand("person_seeds.exs", __DIR__)
end
