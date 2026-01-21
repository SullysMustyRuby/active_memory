defmodule Test.Support.Dogs.Store do
  use ActiveMemory.Store,
    table: Test.Support.Dogs.Dog,
    before_init: [{:run_me, ["Blue"]}]

  def run_me(name) do
    %Test.Support.Dogs.Dog{
      name: name,
      breed: "English PitBull",
      weight: 40,
      fixed?: false
    }
    |> write()
  end

  def initial_state(arg, arg2) do
    {:ok,
     %{
       key: arg,
       next: arg2,
       now: DateTime.utc_now()
     }}
  end
end
