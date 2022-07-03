defmodule ActiveMemory.Adapter.Helpers do
  def to_tuple(%{__struct__: module} = struct, :ets),
    do: build_tuple(module.__meta__.attributes, struct)

  def to_tuple(%{__struct__: module} = struct, :mnesia) do
    module.__meta__.attributes
    |> build_tuple(struct)
    |> Tuple.insert_at(0, module)
  end

  def to_struct(tuple, module, :ets) when is_tuple(tuple),
    do: struct(module, build_struct(module.__meta__.attributes, tuple))

  def to_struct(tuple, module, :mnesia) when is_tuple(tuple) do
    struct(module, build_struct(module.__meta__.attributes, Tuple.delete_at(tuple, 0)))
  end

  defp build_struct(attributes, tuple) do
    attributes
    |> Enum.with_index(fn element, index -> {element, elem(tuple, index)} end)
    |> Enum.into(%{})
  end

  defp build_tuple(attributes, struct) do
    attributes
    |> Enum.into([], fn key -> Map.get(struct, key) end)
    |> List.to_tuple()
  end
end
