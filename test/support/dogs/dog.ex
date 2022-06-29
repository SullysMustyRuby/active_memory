defmodule Test.Support.Dogs.Dog do
  use ActiveMemory.Table, attributes: [:name, :breed, :weight, :fixed?]
end
