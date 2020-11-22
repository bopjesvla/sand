# Sand

Sand is a sandbox for Elixir. **It should not be used in production at this point in time.**

Sand employs AST whitelisting and BEAM features to ensure that untrusted Elixir code can be run without side effects, that memory and CPU usage are limited, and that the atom table is not filled:

```elixir
Sand.run("""
r factorial = fn
  1 -> 1
  n -> n * factorial.(n - 1)
end

factorial.(22222)
""")

# returns {:error, :max_reductions}
```

Well-behaved programs run without a hitch:

```elixir
Sand.run("""
r factorial = fn
  1 -> 1
  n -> n * factorial.(n - 1)
end

factorial.(5)
""")

# returns {:ok, 120, %Sand{...}}
```

## The Whitelist

Sand operates a small whitelist of permitted language constructs. Everything else is forbidden.

Only a subset of Elixir syntax is supported. Additionally, user code cannot access named functions (of the form `Module.function`) except for a small number of pre-imported functions, such as `+/2` and `is_integer/1`. This means that the Elixir standard library is not available in the sandbox. Functions without side effects, such as `Enum.map`, can, however, be re-implemented as anonymous functions in the sandbox.

These are the permitted language constructs:

- The following reserved keywords: `do and or end in true false nil when not else fn` 
- The following inlined operators: `== != > >= < <= + - * / ++ --`
- The inlined `is_*` operators, used for type checking
- These language constructs: `= {} -> %{} | &`
- Variables, atoms, integers, floats, lists, anonymous functions and anonymous function calls
- Binary strings smaller than 64 bytes
- These macros: `case ^ |> if in` 
- The recursion macro `r`, which enables recursion in anonymous functions
- Bracket indexing on maps and keyword lists: `map[key]` 

## Resource Management

Resource management is done at the level of the Erlang VM, not the OS.

By default, a sandbox process will be killed if it uses more than 1 MB in memory, if it performs more than 1 million reductions, or if it runs for more than 10 seconds. Note that these limits are soft: the process is killed only when the monitor notices the transgression. One should anticipate disobedient processes to briefly use more resources than allowed before being killed.

Memory is limited using `max_heap_size`. Computation is limited by monitoring `Process.info(:reductions)`. Run time is limited using `:timer.exit_after`.

## State

Both state and configuration are held in the `%Sand{...}` struct. This struct can be passed as the first argument to `Sand.run/2` and `Sand.assign/2`. Both of those functions return an altered `Sand` struct, holding the new state.

As in IEx, all top-level variables are part of the state:

```elixir
{:ok, 9, box} = Sand.run("""
squares = %{3 => 9, 4 => 16, 5 => 25}
squares[3]
""")

{:ok, 16, _} = Sand.run(box, "squares[4]")
%{3 => 9, 4 => 16, 5 => 25} = Sand.get(box, "squares")
```

Assigning globals can also be done programmatically. This is useful for providing input to user code:

```
user_code = "input[:width] * input[:height]"

Sand.assign("input", %{width: 50, height: 100})
|> Sand.run(user_code)
```

## Atom Renaming

Atoms are not garbage collected. Because of this, all atoms are renamed to a fixed set of atoms when code is parsed. By default, the prefix is set to `sand_atom_`.

```elixir
{:ok, [:sand_atom_0, :sand_atom_1], box} = Sand.run("[:first, :second]")
{:ok, [:sand_atom_0, :sand_atom_2], _} = Sand.run(box, "[:first, :third]")
```

## Configuration

The majority of fields in the `%Sand{...}` struct are configuration options:

```elixir
prefix: "sand_atom_", # the atom prefix
max_heap_size: 125_000, # process memory in words
max_reductions: 1_000_000, # maximum number of reductions per call of Sandbox.run/2
max_vars: 10_000, # Maximum number of variables
timeout: 10_000 # Number of milliseconds before Sandbox.run/2 is aborted
```

Except for the atom prefix, all options can be altered between runs:

```
lil_memory = %Sand{max_heap_size: 10_000}
{:ok, res, new_box} = Sandbox.run(lil_memory, some_user_code)
more_memory = %{ new_box | max_heap_size: 1_000_000}
{:ok, res2, final_box} = Sandbox.run(more_memory, demanding_user_code)
```

## The Recursion Macro

Elixir does not support recursion in anonymous functions:

```elixir
loop = fn -> loop.() end

# ** (CompileError) iex:8: undefined function loop/0
#     (elixir 1.10.4) src/elixir_fn.erl:15: anonymous fn/4 in :elixir_fn.expand/3
#     (stdlib 3.13) lists.erl:1354: :lists.mapfoldl/3
#     (elixir 1.10.4) src/elixir_fn.erl:20: :elixir_fn.expand/3
```

Because anonymous functions are the only functions permitted in Sand, `r`, a macro enabling recursion, is inlined:

```elixir

r loop = fn -> loop.() end
loop.()
```

The syntax is `r [NAME] = fn [BODY] end`.

## This sandbox may not be safe

### CPU usage

BEAM uses preemptive scheduling. The scheduler switches to a different process every 2000 reductions. Because of this, tight loops do not freeze up a core, and the reduction counter will quickly stop the process. However, as I understand it, reduction count does not directly translate to CPU cycles. The cost of each built-in function (e.g. `+/2`) is estimated rather than measured. As such, a malicious process may be able to claim more CPU time than others by performing heavy computations with a relatively low reduction count. I do not know enough about the scheduler to say if this will be a problem.

### Memory usage

Memory usage is checked after garbage collecting, meaning that the actual memory limit is `max_heap_size` plus whatever the user code can claim in 2000 reductions. I have not been able to exceed the max heap size by more than 40% before being killed, but someone might.

### The atom table

I am quite confident that filling the atom table is impossible, but I could be wrong.

### AST whitelisting

AST whitelisting is based on my understanding of the capabilities of each Elixir construct. I may be unaware of certain language features which can be used in malicious ways.

### Unknown unknowns

Most importantly, I built this thing and, at the time of writing, I am the only person who tried to break it. This should not inspire trust.

## Installation

The package can be installed by adding `sand` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sand, "~> 0.1.0"}
  ]
end
```
