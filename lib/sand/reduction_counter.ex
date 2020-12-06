defmodule Sand.ReductionCounter do
  def new(max_count, timeout) do
    pid = self()
    spawn_link fn -> check_reductions(pid, max_count, timeout) end
  end

  def check_reductions(pid, max_r, timeout) do
    case Process.info(pid, :reductions) do
      nil ->
        :ok
      :undefined ->
        :ok
      {:reductions, r} when r >= max_r ->
        Process.exit(pid, :max_reductions)
      {:reductions, _} ->
        if timeout > 0 do
          :timer.sleep(timeout)
        end
        check_reductions(pid, max_r, timeout)
    end
  end

  def stop(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)
  end
end
