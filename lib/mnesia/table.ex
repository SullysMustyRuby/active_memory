defmodule ActiveMemory.Mnesia.Table do
  defmacro __using__(opts) do
    opts = Macro.expand(opts, __CALLER__)

    quote do
      import unquote(__MODULE__)

      opts = unquote(opts)

      @table_attrs Keyword.get(opts, :attributes)

      use Memento.Table, attributes: @table_attrs

      def new(attributes) do
        %__MODULE__{}
        |> Map.merge(attributes)
      end

      def __meta__, do: %{attributes: @table_attrs}
    end
  end
end
