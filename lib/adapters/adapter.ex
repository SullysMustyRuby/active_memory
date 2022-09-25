defmodule ActiveMemory.Adapters.Adapter do
  @moduledoc false

  @callback all(atom()) :: list(map())

  @callback create_table(atom(), map()) :: :ok | {:error, any()}

  @callback delete(map(), atom()) :: :ok | {:error, any()}

  @callback delete_all(atom()) :: :ok | {:error, any()}

  @callback one(map(), atom()) :: {:ok, map()} | {:error, any()}

  @callback one(list(any()), atom()) :: {:ok, map()} | {:error, any()}

  @callback select(map(), atom()) :: {:ok, list(map())} | {:error, any()}

  @callback select(list(any()), atom()) :: {:ok, list(map())} | {:error, any()}

  @callback write(map(), atom()) :: {:ok, map()} | {:error, any()}
end
