defmodule ActiveMemory.Adapter.Helpers do
  def to_tuple(%{__struct__: module} = struct) do
    module.__meta__.attributes
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
  end

  def to_struct(ets_tuple, module) when is_tuple(ets_tuple) do
    attributes =
      module.__meta__.attributes
      |> Enum.with_index(fn element, index -> {element, elem(ets_tuple, index)} end)
      |> Enum.into(%{})

    struct(module, attributes)
  end
end
