defmodule ActiveMemory.Ets.Table do
  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      opts = unquote(opts)

      @table_attrs Keyword.get(opts, :attributes)

      defstruct @table_attrs

      def new(attributes) when is_map(attributes) do
        %__MODULE__{}
        |> Map.merge(attributes)
      end

      def to_tuple(%__MODULE__{} = struct) do
        @table_attrs
        |> Enum.into([], fn key -> Map.get(struct, key) end)
        |> List.to_tuple()
      end

      def to_struct(ets_tuple) when is_tuple(ets_tuple) do
        @table_attrs
        |> Enum.with_index(fn element, index -> {element, elem(ets_tuple, index)} end)
        |> Enum.into(%{})
        |> new()
      end
    end
  end
end

# defstruct Definition.struct_fields(@table_attrs)
# def struct_fields do
#   [{:__meta__, ActiveMemory.Ets.Table} | attributes]
# end

# [:name, :breed, :weight, :fixed?]
# {"gem", "Shaggy Black Lab", "30", false}
