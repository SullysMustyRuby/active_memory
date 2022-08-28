defmodule ActiveMemory.Table.Attributes do
  defmacro __using__(_) do
    quote do
      import ActiveMemory.Table.Attributes, only: [attributes: 2]

      @primary_key nil
      @timestamps_opts []
      @foreign_key_type :uuid
      @attributes_prefix nil
      @attributes_context nil
      @field_source_mapper fn x -> x end

      Module.register_attribute(__MODULE__, :active_memory_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_fields, accumulate: true)
      # Module.register_attribute(__MODULE__, :active_memory_virtual_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_query_fields, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_field_sources, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_assocs, accumulate: true)
      # Module.register_attribute(__MODULE__, :active_memory_embeds, accumulate: true)
      # Module.register_attribute(__MODULE__, :active_memory_raw, accumulate: true)
      Module.register_attribute(__MODULE__, :active_memory_autogenerate, accumulate: true)
      # Module.register_attribute(__MODULE__, :active_memory_autoupdate, accumulate: true)
      # Module.register_attribute(__MODULE__, :active_memory_redact_fields, accumulate: true)
      # Module.put_attribute(__MODULE__, :active_memory_derive_inspect_for_redacted_fields, true)
      Module.put_attribute(__MODULE__, :active_memory_autogenerate_uuid, nil)
    end
  end

  defmacro attributes(source, do: block) do
    attributes(__CALLER__, source, true, :id, block)
  end

  defp attributes(caller, source, meta?, type, block) do
    prelude =
      quote do
        @after_compile ActiveMemory.Table.Attributes
        Module.register_attribute(__MODULE__, :active_memory_changeset_fields, accumulate: true)
        Module.register_attribute(__MODULE__, :active_memory_struct_fields, accumulate: true)

        meta? = unquote(meta?)
        source = unquote(source)
        prefix = @attributes_prefix
        context = @attributes_context

        meta = %{
          state: :built,
          source: source,
          prefix: prefix,
          context: context,
          attributes: __MODULE__
        }

        Module.put_attribute(__MODULE__, :active_memory_struct_fields, {:__meta__, meta})

        if @primary_key == nil do
          @primary_key {:uuid, :string, autogenerate: true}
        end

        primary_key_fields =
          case @primary_key do
            false ->
              []

            {name, type, opts} ->
              ActiveMemory.Table.Attributes.__field__(
                __MODULE__,
                name,
                type,
                [primary_key: true] ++ opts
              )

              [name]

            other ->
              raise ArgumentError, "@primary_key must be false or {name, type, opts}"
          end

        try do
          import ActiveMemory.Table.Attributes
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        primary_key_fields = @active_memory_primary_keys |> Enum.reverse()
        autogenerate = @active_memory_autogenerate |> Enum.reverse()
        # autoupdate = @active_memory_autoupdate |> Enum.reverse()
        fields = @active_memory_fields |> Enum.reverse()
        query_fields = @active_memory_query_fields |> Enum.reverse()
        # virtual_fields = @active_memory_virtual_fields |> Enum.reverse()
        field_sources = @active_memory_field_sources |> Enum.reverse()
        # assocs = @active_memory_assocs |> Enum.reverse()
        # embeds = @active_memory_embeds |> Enum.reverse()
        # redacted_fields = @active_memory_redact_fields
        loaded =
          ActiveMemory.Table.Attributes.__loaded__(__MODULE__, @active_memory_struct_fields)

        # if redacted_fields != [] and not List.keymember?(@derive, Inspect, 0) and
        #      @active_memory_derive_inspect_for_redacted_fields do
        #   @derive {Inspect, except: @active_memory_redact_fields}
        # end

        defstruct Enum.reverse(@active_memory_struct_fields)

        def __changeset__ do
          %{unquote_splicing(Macro.escape(@active_memory_changeset_fields))}
        end

        def __attributes__(:prefix), do: unquote(prefix)
        # def __attributes__(:source), do: unquote(source)
        def __attributes__(:fields), do: unquote(Enum.map(fields, &elem(&1, 0)))
        def __attributes__(:query_fields), do: unquote(Enum.map(query_fields, &elem(&1, 0)))
        def __attributes__(:primary_key), do: unquote(primary_key_fields)
        def __attributes__(:hash), do: unquote(:erlang.phash2({primary_key_fields, query_fields}))
        # def __attributes__(:read_after_writes), do: unquote(Enum.reverse(@active_memory_raw))

        def __attributes__(:autogenerate_uuid),
          do: unquote(Macro.escape(@active_memory_autogenerate_uuid))

        def __attributes__(:autogenerate), do: unquote(Macro.escape(autogenerate))
        # def __attributes__(:autoupdate), do: unquote(Macro.escape(autoupdate))
        def __attributes__(:loaded), do: unquote(Macro.escape(loaded))
        # def __attributes__(:redact_fields), do: unquote(redacted_fields)
        # def __attributes__(:virtual_fields), do: unquote(Enum.map(virtual_fields, &elem(&1, 0)))

        # def __attributes__(:query) do
        #   %Ecto.Query{
        #     from: %Ecto.Query.FromExpr{
        #       source: {unquote(source), __MODULE__},
        #       prefix: unquote(prefix)
        #     }
        #   }
        # end

        for clauses <-
              ActiveMemory.Table.Attributes.__attributes__(
                fields,
                field_sources
              ),
            {args, body} <- clauses do
          def __attributes__(unquote_splicing(args)), do: unquote(body)
        end
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  # defmacro field(name, type \\ :string, opts \\ []) do
  #   %{name: name, type: type}
  # end

  defmacro field(name, type \\ :string, opts \\ []) do
    quote do
      ActiveMemory.Table.Attributes.__field__(
        __MODULE__,
        unquote(name),
        unquote(type),
        unquote(opts)
      )
    end
  end

  # defmacro has_many(name, struct, opts \\ []) do
  #   %{type: :has_many, name: name, struct: struct, opts: opts}
  # end

  @doc false
  def __field__(mod, name, type, opts) do
    # Check the field type before we check options because it is
    # better to raise unknown type first than unsupported option.
    # type = check_field_type!(mod, name, type, opts)

    # if type == :any && !opts[:virtual] do
    #   raise ArgumentError,
    #         "only virtual fields can have type :any, " <>
    #           "invalid type for field #{inspect(name)}"
    # end

    # check_options!(type, opts, @field_opts, "field/3")
    Module.put_attribute(mod, :active_memory_changeset_fields, {name, type})
    # validate_default!(type, opts[:default], opts[:skip_default_validation])
    define_field(mod, name, type, opts)
  end

  @doc false
  def __loaded__(module, struct_fields) do
    case Map.new([{:__struct__, module} | struct_fields]) do
      %{__meta__: meta} = struct -> %{struct | __meta__: Map.put(meta, :state, :loaded)}
      struct -> struct
    end
  end

  @doc false
  def __after_compile__(%{module: module} = env, _) do
    # If we are compiling code, we can validate associations now,
    # as the Elixir compiler will solve dependencies.
    #
    # TODO: Use Code.can_await_module_compilation?/0 from Elixir v1.10+.
    # if Process.info(self(), :error_handler) == {:error_handler, Kernel.ErrorHandler} do
    #   for name <- module.__attributes__(:associations) do
    #     assoc = module.__attributes__(:association, name)

    #     case assoc.__struct__.after_compile_validation(assoc, env) do
    #       :ok ->
    #         :ok

    #       {:error, message} ->
    #         IO.warn(
    #           "invalid association `#{assoc.field}` in schema #{inspect(module)}: #{message}",
    #           Macro.Env.stacktrace(env)
    #         )
    #     end
    #   end
    # end

    :ok
  end

  @doc false
  # def __attributes__(fields, field_sources, assocs, embeds, virtual_fields) do
  def __attributes__(fields, field_sources) do
    load =
      for {name, type} <- fields do
        if alias = field_sources[name] do
          {name, {:source, alias, type}}
        else
          {name, type}
        end
      end

    dump =
      for {name, type} <- fields do
        {name, {field_sources[name] || name, type}}
      end

    field_sources_quoted =
      for {name, _type} <- fields do
        {[:field_source, name], field_sources[name] || name}
      end

    types_quoted =
      for {name, type} <- fields do
        {[:type, name], Macro.escape(type)}
      end

    # virtual_types_quoted =
    #   for {name, type} <- virtual_fields do
    #     {[:virtual_type, name], Macro.escape(type)}
    #   end

    # assoc_quoted =
    #   for {name, refl} <- assocs do
    #     {[:association, name], Macro.escape(refl)}
    #   end

    # assoc_names = Enum.map(assocs, &elem(&1, 0))

    # embed_quoted =
    #   for {name, refl} <- embeds do
    #     {[:embed, name], Macro.escape(refl)}
    #   end

    # embed_names = Enum.map(embeds, &elem(&1, 0))

    single_arg = [
      {[:dump], dump |> Map.new() |> Macro.escape()},
      {[:load], load |> Macro.escape()}
      # {[:associations], assoc_names},
      # {[:embeds], embed_names}
    ]

    catch_all = [
      {[:field_source, quote(do: _)], nil},
      {[:type, quote(do: _)], nil}
      # {[:virtual_type, quote(do: _)], nil},
      # {[:association, quote(do: _)], nil},
      # {[:embed, quote(do: _)], nil}
    ]

    [
      single_arg,
      field_sources_quoted,
      types_quoted,
      # virtual_types_quoted,
      # assoc_quoted,
      # embed_quoted,
      catch_all
    ]
  end

  defp define_field(mod, name, type, opts) do
    virtual? = opts[:virtual] || false
    pk? = opts[:primary_key] || false
    put_struct_field(mod, name, Keyword.get(opts, :default))

    # if Keyword.get(opts, :redact, false) do
    #   Module.put_attribute(mod, :ecto_redact_fields, name)
    # end

    # if virtual? do
    #   Module.put_attribute(mod, :ecto_virtual_fields, {name, type})
    # else
    # source = opts[:source] || Module.get_attribute(mod, :field_source_mapper).(name)

    # if not is_atom(source) do
    #   raise ArgumentError,
    #         "the :source for field `#{name}` must be an atom, got: #{inspect(source)}"
    # end

    # if name != source do
    #   Module.put_attribute(mod, :ecto_field_sources, {name, source})
    # end

    # if raw = opts[:read_after_writes] do
    #   Module.put_attribute(mod, :ecto_raw, name)
    # end

    # case gen = opts[:autogenerate] do
    #   {_, _, _} ->
    #     store_mfa_autogenerate!(mod, name, type, gen)

    #   true ->
    #     store_type_autogenerate!(mod, name, source || name, type, pk?)

    #   _ ->
    #     :ok
    # end

    # if raw && gen do
    #   raise ArgumentError, "cannot mark the same field as autogenerate and read_after_writes"
    # end

    if pk? do
      Module.put_attribute(mod, :active_memory_primary_keys, name)
    end

    if Keyword.get(opts, :load_in_query, true) do
      Module.put_attribute(mod, :active_memory_query_fields, {name, type})
    end

    Module.put_attribute(mod, :active_memory_fields, {name, type})
    # end
  end

  defp put_struct_field(mod, name, assoc) do
    fields = Module.get_attribute(mod, :active_memory_struct_fields)

    if List.keyfind(fields, name, 0) do
      raise ArgumentError,
            "field/association #{inspect(name)} already exists on schema, you must either remove the duplication or choose a different name"
    end

    Module.put_attribute(mod, :active_memory_struct_fields, {name, assoc})
  end
end
