defmodule Test.Support.People.Store do
  use ActiveMemory.Store,
    table: Test.Support.People.Person,
    before_init: [load_seeds: []]

  def load_seeds do
    file = Path.expand("person_seeds.exs", __DIR__)
    {seeds, _other} = Code.eval_file(file)
    Enum.each(seeds, &write(&1))
  end
end
