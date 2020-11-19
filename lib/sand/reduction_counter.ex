defmodule Sand.ReductionCounter do
  def new(max_count) do
    pid = self()
    spawn_link fn -> check_reductions(pid, max_count) end
  end

  def check_reductions(pid, max_r) do
    case Process.info(pid, :reductions) do
      :undefined ->
        :ok
      {:reductions, r} when r >= max_r ->
        IO.inspect("KILLING")
        Process.exit(pid, :max_reductions)
      {:reductions, _} ->
        :timer.sleep(100)
        check_reductions(pid, max_r)
    end
  end

  def stop(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)
  end
end
