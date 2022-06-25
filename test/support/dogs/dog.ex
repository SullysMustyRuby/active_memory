defmodule Test.Support.Dogs.Dog do
  use MnesiaCompanion.Ets.Table, attributes: [:name, :breed, :weight, :fixed?]
end
