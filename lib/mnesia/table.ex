defmodule ActiveMemory.Mnesia.Table do
  alias ActiveMemory.Definition

  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      opts = unquote(opts)

      @table_attrs Keyword.get(opts, :attributes)
      @query_map Definition.build_query_map(@table_attrs)
      @match_head Definition.build_match_head(@query_map)

      defstruct @table_attrs

      def to_tuple(%__MODULE__{} = struct) do
        @table_attrs
        |> Enum.into([], fn key -> Map.get(struct, key) end)
        |> List.to_tuple()
      end

      def to_struct(ets_tuple) when is_tuple(ets_tuple) do
        attributes =
          @table_attrs
          |> Enum.with_index(fn element, index -> {element, elem(ets_tuple, index)} end)
          |> Enum.into(%{})

        struct(__MODULE__, attributes)
      end

      def __meta__,
        do: %{attributes: @table_attrs, query_map: @query_map, match_head: @match_head}
    end
  end
end
