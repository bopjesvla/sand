defmodule Sand.Rfn do
  defmacro r({:=, _, [name, {:fn, meta, [c|_clauses]} = f]}) do
    var = if is_atom(name), do: Macro.var(name, nil), else: name
    n = num_args(c)
    args = n_args(n, [])
    namedf = quote do
      fn (unquote(var)) -> unquote(f) end
    end
    combinator_fun = combinator_ast(namedf, args, meta)
    quote do
      combinator = unquote(combinator_fun)
      unquote(name) = combinator.(combinator)
    end
  end

  defp combinator_ast(namedf, args, meta) do
    xvar = Macro.var(:x, __MODULE__)
    # fn (args...) -> xvar.(xvar).(args...) end

    inner = quote do
      fn unquote_splicing(args) ->
        unquote(xvar).(unquote(xvar)).(unquote_splicing(args))
      end
    end

    # fn (xvar) -> var.(inner) end
    quote do
      fn unquote(xvar) -> unquote(namedf).(unquote(inner)) end
    end
  end

  # defp fn_ast(vars, body, meta) do
  #   {:fn, meta, [{:->, meta, [vars, body]}]}
  # end

  # create n local args
  defp n_args(0, args) do
    args
  end
  defp n_args(n, args) do
    n_args(n - 1, [Macro.var(:"a#{n - 1}", __MODULE__) | args])
  end

  defp num_args({:->, _, [fn_head | _fn_body]}) do
    num_args_fn_head(fn_head)
  end
  defp num_args_fn_head([{:when, _, args} | _]) do
    length(args) - 1
  end
  defp num_args_fn_head(vars) when is_list(vars) do
    length(vars)
  end

  defp is_arg({a, _m, c}) when is_atom(a) and is_atom(c), do: :true
  defp is_arg(_), do: :false
end
