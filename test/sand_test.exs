defmodule SandTest do
  use ExUnit.Case
  doctest Sand

  @basicmodule File.read!(~s'priv/basic_module.ex')
  @core [{Kernel.SpecialForms, case: 2}, {Kernel, if: 2, in: 2}]
  @myfunctions [{Sand.Functions, concat: 2}]

  defmacro undef(fun) do
    quote do
      %CompileError{description: unquote("undefined function #{fun}")}
    end
  end

  test "parsing and running" do
    lil_memory = %Sand{max_heap_size: 100_000, max_reductions: 10_000_000}

    assert {:error, :killed} = Sand.run(lil_memory, """
    r fork = fn
    1 -> 1
    n -> {fork.(n - 1), fork.(n - 1)}
    end

    fork.(10000)
    """)

    before = :erlang.system_time(:millisecond)

    assert {:ok, n, _} = Sand.run(%Sand{max_reductions: 10_000_000}, """
    r fork = fn
    1 -> 1.23456889565645743734732434234367
    n -> {fork.(n - 1), fork.(n - 1)}
    end

    fork.(10)
    """)

    # IO.inspect n
    IO.inspect :erlang.system_time(:millisecond) - before

    assert {:error, :killed} = Sand.run(lil_memory, """
    r fork = fn
    1 -> [3]
    n -> fork.(n - 1) ++ fork.(n - 1)
    end

    fork.(10000)
    """)

    before = :erlang.system_time(:millisecond)

    assert {:error, :max_reductions} = Sand.run(lil_memory, """
    r loop = fn -> loop.() end
    loop.()
    """)

    IO.inspect :erlang.system_time(:millisecond) - before

    Process.flag(:trap_exit, true)
    assert {:ok, 6, _} = Sand.run(~s/1 + 5/)
    assert {:ok, 1, _} = Sand.run(~s/1 = 1/)
    assert Sand.sandbox(~s/"a" = 5/)
    assert {:error, _} = Sand.run(~s/"a" = 5/)
    assert {:error, {undef("a/0"), _}} = Sand.run(~s/a()/)
    assert {:ok, {1}, _} = Sand.run(~s/{1}/)
    assert {:error, {undef("a/0"), _}} = Sand.run(~s/[1,a(),a(),a(),4]/)
    assert {:error, {%CompileError{description: "invalid call a(b)(c)"},_}} =
      Sand.run(~s/a(b)(c)/)
    assert {:ok, 1, %Sand{bindings: [{a, _}], vars: %{"zzz" => a}}} =
      Sand.run(~s/zzz = & &1; zzz.(1)/)
    Sand.sandbox(~s/zzz.()/)

    catch_error Sand.sandbox(~s/:is_binary.is_binary(:+)/)

    assert {:ok, 5, _} = Sand.run(~s/%{3 => 5}[3]/)
    assert {:error, _} = Sand.run(~s/%{a: 2}.a/)
    assert {:ok, nil, _} = Sand.run(~s/%{a: 2}[3]/)
    Sand.run(~s/%{%{x: 2} | x: 3}/)
    Sand.run(~s/x = 1; ^x = 1/)
    {:error, {undef("self/0"), _}} = Sand.run(~s/self()/)
    {:error, {undef("require/1"), _}} = Sand.run(~s/require Kernel/)
    {:error, {undef("use/1"), _}} = Sand.run(~s/use Kernel/)
    {:error, {undef("import/1"), _}} = Sand.run(~s/import Kernel/)
    Sand.run(~s/a = true; if a, do: a/)
    # Sand.ensure_safety(~s/fn x -> x end/)
    Sand.run(~s/case 5 do 5 -> 3 end/)
    Sand.run(~s/x = 'zzz'/)
    Sand.run(~s/1 |> is_integer/)
    catch_error Sand.sandbox(~s/<<"a", "b">>/)
    Sand.run("""
    z = 1; fn
      [_q | y] -> y
      %{x: 1} -> 5
    end
    """)
    {:error, {_, _}} = Sand.run(~s/~e(a b)/)
    {:error, {_, _}} = Sand.run(~s/:self.self()/)
    # {:ok, 1, _} = Sand.run("a=1")
    Sand.sandbox(":a")

    {:ok, [:sand_atom_0, :sand_atom_1], box} = Sand.run("[:first, :second]")
    {:ok, [:sand_atom_0, :sand_atom_2], _} = Sand.run(box, "[:first, :third]")

    Sand.run("{1, 2, 3}")
    Sand.run("{1, 2}")
    Sand.run("x = %{a: 2}")

    # Sand.test(:a, [2,3])

    lil_memory = %Sand{max_heap_size: 100000, max_reductions: :infinity}

    assert {:ok, 120, _} = Sand.run(lil_memory, """
    r factorial = fn
    1 -> 1
    n -> n * factorial.(n - 1)
    end

    factorial.(5)
    """)

    assert {:error, :killed} = Sand.run(lil_memory, """
    r factorial = fn
    1 -> 1
    n -> n * factorial.(n - 1)
    end

    factorial.(22222)
    """)

    # import Sand.Rfn

    # r factorial = fn
    #   1 -> 1
    #   n -> n * factorial.(n - 1)
    # end

    # 120 = factorial.(5)
  end

  test "parallel" do
    before = :erlang.system_time(:millisecond)
    Enum.map(1..50, &Task.async fn -> &1; Sand.run(%Sand{max_reductions: 10_000_000}, "r loop = fn -> loop.() end; loop.()") end) |> Enum.map(&Task.await/1)
    IO.inspect :erlang.system_time(:millisecond) - before
  end

  test "basic module" do
    Code.eval_string(@basicmodule)

    assert {:error, {undef("defmodule/2"), _}} = Sand.run(@basicmodule)
  end

  test "assign" do
    assert {:ok, "yo", _} = Sand.assign("a", "yo")
    |> Sand.run("a")
    |> IO.inspect

    assert {:ok, n, _} = Sand.assign_unsafe("random", &:rand.uniform/1)
    |> IO.inspect
    |> Sand.run("random.(5)")

    assert n in 0..5
  end

  test "no imports" do
    catch_error Code.eval_string(~s/if 1 do 5 end/, [], requires: [Kernel], macros: [])
    catch_error Code.eval_string(~s/1 + 5/, [], requires: [Kernel], macros: [], functions: [])
    Code.eval_string(~s/if 1 do 5 end/, [], requires: [Kernel], macros: @core, aliases: [])
    Code.eval_string(~s/if 1 do 5 end/, [], requires: [Kernel], macros: @core, aliases: [])
    Code.eval_string(~s/<<"a", "b">>/, [], requires: [Kernel], macros: @core, functions: [])
    {"aa", []} = Code.eval_string(~s/concat("a", "a")/, [], requires: [Kernel, Sand.Functions], macros: @core, functions: @myfunctions)
    Code.eval_string("""
    a = "a"
    x = 5
    """, [])
    Code.eval_string(~s/<<"a", "b">> = "ab"/, [], requires: [Kernel], macros: @core)
    Code.eval_string(~s/<<"a", "b">>/, [], requires: [Kernel], macros: [{Kernel, <>: 2}])
    Code.eval_string(~s/5 + 3/, [], requires: [Kernel], macros: [{Kernel, <>: 2}])
  end

  test "static atoms encoder" do
    encoder = fn
      string, _meta ->
        {:ok, {:atom, string}}
    end
    Code.string_to_quoted!("a = 1", static_atoms_encoder: encoder)
    # Code.string_to_quoted!("a=1", static_atoms_encoder: encoder)
  end
end
