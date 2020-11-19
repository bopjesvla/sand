# defmodule Sand.Server do
#   use GenServer

#   alias Sand.ReductionCounter

#   @max_reductions 10_000_000
#   @max_reductions_total 10_000_000

#   # management

#   def start_link(name, args) do
#     # IO.inspect args
#     GenServer.start_link(__MODULE__, args, name: name, timeout: 10000)
#   end

#   # API

#   defp call(id, arg) do
#     # via = via_tuple(id)
#     # try do
#     res = GenServer.call(id, arg, 10000)
#     # if res == {:error, :timeout} do
#     #   GameSupervisor.kill_game(via)
#     # end
#     # res
#     # catch
#     #   :exit, {s, {_, :call, _}} ->
#     #     GameSupervisor.kill_game(via)
#     #     {:error, s}
#     #   :exit, s ->
#     #     GameSupervisor.kill_game(via)
#     #     {:error, s}
#     # end
#   end

#   def move(id, player, move) do
#     id
#     |> call({:move, player, move})
#   end

#   def info(id) do
#     id
#     |> call({:info})
#   end

#   def info(id, player) do
#     id
#     |> call({:info, player})
#   end

#   def stop(id) do
#     id
#     |> GenServer.stop
#   end

#   # callbacks

#   def init(g) do
#     Process.flag(:max_heap_size, 1_000_000)

#     if g[:init_script] do
#       {out, box} = Sand.run(g[:init_script])
#     end
#     pid = ReductionCounter.new(@max_reductions)

#     game = Game.new(%{size: g.setup.size, id: Map.get(g, :id), side_effects: side_effects})
#     |> Game.exec!(g.setup.script)
#     |> Game.set_constant_seed(g.seed)
#     |> Game.start

#     ReductionCounter.stop(pid)

#     {:ok, %{game: game}}
#   end

#   def handle_call({:move, player, move}, _, state) do
#     pid = ReductionCounter.new(@max_reductions)

#     reply =
#       case Game.make_valid_move(state.game, player, move) do
#         {:ok, %{info: %{status: %{ongoing: false, scores: s}}} = g} ->
#           {:stop, :normal, {:ok, :ended}, %{state | game: g}}
#         {:ok, g} ->
#           {:reply, {:ok, :updated}, %{state | game: g}}
#         {:error, e} ->
#           {:reply, {:error, e}, state}
#       end

#     ReductionCounter.stop(pid)

#     reply
#   end

#   def handle_call({:info}, _, state) do
#     {:reply, {:ok, state.game.info}, state}
#   end

#   def handle_call({:info, player}, _, state) do
#     {:reply, {:ok, Game.mask_info(state.game.info, player)}, state}
#   end
# end
