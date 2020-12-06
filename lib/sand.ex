defmodule Sand do
  @moduledoc """
  Documentation for Sand.
  """

  if System.version != "1.10.4" do
    IO.warn("UNSAFE! UNCLEAN! You're using Elixir v#{System.version}! Sand has only been tested for v1.10.4!")
  end

  if :erlang.system_info(:otp_release) != '23' do
    IO.warn("UNSAFE! UNCLEAN! You're using Erlang/OTP #{:erlang.system_info(:otp_release)}! Sand has only been tested for v23")
  end

  defstruct counter: 0, # variable book-keeping
    vars: %{},
    bindings: [],

    # CONFIGURATION
    prefix: "sand_atom_", # the prefix the sandbox atoms get
    max_heap_size: 125_000, # process memory in words
    max_reductions: 1_000_000, # maximum number of reductions per call of Sandbox.run/2
    max_vars: 10_000, # Maximum number of variables
    timeout: 10_000, # Number of milliseconds before Sandbox.run/2 is aborted
    reduction_monitor_timeout: 0 # Number of ms the reduction monitor sleeps between checks

  @safe_inlined %{==: 2, !=: 2, >: 2, >=: 2, <: 2, <=: 2, +: 2, -: 2, *: 2, /: 2, ++: 2, --: 2}
  @safe_unary %{is_atom: 1,
               is_binary: 1,
               is_bitstring: 1,
               is_boolean: 1,
               is_float: 1,
               is_function: 1,
               is_integer: 1,
               is_list: 1,
               is_map: 1,
               is_map_key: 1,
               is_nil: 1,
               is_number: 1,
               is_pid: 1,
               is_port: 1,
               is_reference: 1,
               is_tuple: 1}
  @safe_any_arity ~w[{} %{} fn true nil false end]a
  @safe_ops %{=: 2, ->: 2, |: 2, &: 1}
  @safe_macros [
    {Kernel.SpecialForms, [case: 2, ^: 1] |> Enum.sort},
    {Kernel, [|>: 2, if: 2, in: 2] |> Enum.sort},
    {Sand.Rfn, [r: 1] |> Enum.sort},
    {Sand.Loader, [load: 2] |> Enum.sort}
  ]
  @kernel_imports Map.merge(@safe_inlined, @safe_unary)
  @safe_imports [
    {Kernel, @kernel_imports |> Enum.sort},
    {Sand.Functions, [access_get: 2, concat: 2] |> Enum.sort},
  ]
  @safe_macro_kw for {_m, l} <- @safe_macros, pair <- l, do: pair, into: %{}
  @safe_reserved %{do: 1, and: 2, or: 2, when: 2, not: 1, else: 1}

  @safe_all Enum.reduce(
    [@safe_unary, @safe_inlined, @safe_ops, @safe_macro_kw, @safe_reserved], &Map.merge/2
  )

  @safe_all_keys Map.keys(@safe_all)

  @safe_atoms @safe_all_keys ++ @safe_any_arity

  @safe_str Enum.map(@safe_atoms, &to_string/1)

  def var(name, acc) do
    acc = if acc.vars[name] do
      acc
    else
      ignore = case name do "_" <> _ -> "_"; _ -> "" end
      new_vars = Map.put(acc.vars, name, String.to_atom("#{ignore}#{acc.prefix}#{acc.counter}"))
      %{acc | counter: acc.counter + 1, vars: new_vars}
    end
    if acc.counter > acc.max_vars do
      raise "can't have that many variables!"
    end
    {acc.vars[name], acc}
  end

  def muzzle(box \\ %Sand{}, quoted) do
    Macro.prewalk(quoted, box, &safe/2)
  end

  def safe_quote(code) do
    encoder = fn
      macro, _meta when macro in @safe_str ->
        {:ok, String.to_atom(macro)}
      string, _meta when byte_size(string) > 63 ->
        raise "variable name `#{string}` is too long"
      string, _meta ->
        {:ok, {:atom, string}}
    end
    Code.string_to_quoted!(code, static_atoms_encoder: encoder)
  end

  def sandbox(box \\ %Sand{}, code) do
    quoted = safe_quote(code)
    # |> IO.inspect

    # IO.inspect(["in: ", quoted])

    muzzle(box, quoted)
  end

  def run(box \\ %Sand{}, binary_or_quoted) do
    me = self()

    pid = spawn fn ->
      if box.timeout do
        :timer.exit_after(box.timeout, :kill)
      end

      # set process memory
      Process.flag(:max_heap_size, %{size: box.max_heap_size, kill: true})

      pid = Sand.ReductionCounter.new(box.max_reductions, box.reduction_monitor_timeout)

      # monitor number of calculations
      res = run_without_cpu_memory_monitoring(box, binary_or_quoted)
      # {:ok, res}

      Sand.ReductionCounter.stop(pid)

      # TODO: maybe check output size?
      send(me, {:sand_output, res})
    end

    Process.monitor(pid)

    receive do
      {:sand_output, {out, newbox}} ->
        {:ok, out, newbox}
      {:DOWN, _, :process, ^pid, reason} ->
        {:error, reason}
    end
  end

  def run_without_cpu_memory_monitoring(box \\ %Sand{}, code)
  def run_without_cpu_memory_monitoring(box, code) when is_binary(code) do
    {quoted, new_box} = sandbox(box, code)
    run_unsafe(new_box, quoted)
  end

  def run_unsafe(box, quoted) do
    opts = [
      requires: [Kernel, Sand.Functions],
      macros: @safe_macros,
      functions: @safe_imports,
      aliases: []
    ]

    {out, bindings} =
      try do
        Code.eval_quoted(quoted, box.bindings, opts)
      rescue
        e ->
          reraise fix_error(box, e), __STACKTRACE__
      end

    {out, %{box | bindings: bindings}}
  end

  def safe(_, {:error, _} = err) do
    {nil, err}
  end

  def safe({:__aliases__, _, [atom: name]}, acc) do
    var(name, acc)
  end

  def safe({:atom, name}, acc) do
    var(name, acc)
    # {atom, new_acc} = var(name, acc)
    # {{atom, [], []}, new_acc}
  end

  def safe(x, acc) do
    {safe(x), acc}
  end

  def safe({x, _, args} = s)
  when x in @safe_any_arity or :erlang.map_get(x, @safe_all) == length(args) do
    s
  end

  def safe({:., _, [Access, :get]}) do
    :access_get
  end

  # def safe({:=, l, [{:<>, l2, arg}, righthandside]}) do
  #   IO.inspect l2
  #   {:=, l, [{:<>, l2, arg}, righthandside]}
  # end

  def safe({:<>, l, arg}) do
    {:concat, l, arg}
  end

  def safe({:., _, [_]} = s) do
    s
  end

  # def safe({:&, l1, [{:/, l2, [{:__aliases__, _, [atom: name]}, {:atom, arg2}]}]}) do
  # end

  # # Enum.map(l, f) to enum_map_2.(l, f)
  # def safe({{:., l, [{:__aliases__, _, [atom: name]}, {:atom, arg2}]}, l, arg}) do
  #   case arg1 do

  #   end
  #   {:dot, l, [1,2]}
  # end

  # def safe({:., l, arg}) do
  #   IO.inspect(arg)
  #   {:dot, l, arg}
  # end

  def safe({{:atom, _}, _, _} = s) do
    s
  end

  def safe({{_, _, _}, _, _} = s) do
    s
  end

  def safe({:__block__, _, _} = s) do
    s
  end

  def safe({op, _, _}) do
    raise "Function/operator #{op} is not allowed"
  end

  def safe(x) when (is_binary(x) and byte_size(x) < 64) or is_integer(x) or is_float(x) or is_list(x) or (is_atom(x) and x in @safe_atoms) do
    x
  end

  def safe({a, b}) do
    {a, b}
  end

  def safe(x) when is_atom(x) do
    raise "Atom #{x} is not allowed"
  end

  def safe(x) when is_binary(x) do
    raise "Binaries larger than 64 bytes are not allowed"
  end

  def fix_error(box, %{description: desc} = e) do
    var_name = fn var_string ->
      Enum.find(box.vars, {"", var_string}, fn
        {_, x} -> "#{x}" == var_string
        _ -> false
      end)
      |> elem(0)
    end
    %{e | description: Regex.replace(~r/_?#{box.prefix}\d+/, desc, var_name)}
  end

  def fix_error(_box, e) do
    e
  end

  def assign(box \\ %Sand{}, name, value) when is_binary(name) do
    if is_function(value) do
      raise "cannot safely assign a function"
    else
      case run(box, "#{name} = #{inspect value}") do
        {:ok, _res, new_box} ->
          new_box
        {:error, e} ->
          raise e
      end
    end
  end

  def assign_unsafe(box \\ %Sand{}, name, value) when is_binary(name) do
    {sandbox_var, new_box} = var(name, box)
    %{new_box | bindings: Keyword.put(new_box.bindings, sandbox_var, value)}
  end

  def get_nested(box, keypath) do
    # {sandbox_var, _new_box} = var(name, box)
    # var = Keyword.get(box.bindings, sandbox_var)
    # if keypath == [] do
    #   var
    # else
    var_if_atom = fn
      name when is_atom(name) ->
        {sandbox_var, _new_box} = var("#{name}", box); sandbox_var
      e ->
        e
    end
    sand_keypath = Enum.map(keypath, var_if_atom)
    get_in box.bindings, sand_keypath
  end

  def get(box, name) do
    {sandbox_var, _new_box} = var("#{name}", box)
    Keyword.get(box.bindings, sandbox_var)
  end
end
