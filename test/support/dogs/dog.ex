defmodule Test.Support.Dogs.Dog do
  use ActiveMemory.Ets.Table, attributes: [:name, :breed, :weight, :fixed?]
end
