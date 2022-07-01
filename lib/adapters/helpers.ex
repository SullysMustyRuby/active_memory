defmodule ActiveMemory.Adapter.Helpers do
  def to_tuple(%{__struct__: module} = struct) do
    module.__meta__.attributes
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
    |> Tuple.insert_at(0, module)
  end

  def to_struct(tuple, module) when is_tuple(tuple) do
    attributes_tuple = Tuple.delete_at(tuple, 0)

    attributes =
      module.__meta__.attributes
      |> Enum.with_index(fn element, index -> {element, elem(attributes_tuple, index)} end)
      |> Enum.into(%{})

    struct(module, attributes)
  end
end
