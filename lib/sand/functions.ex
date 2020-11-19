defmodule Sand.Functions do
  def concat(a, b) when is_binary(a) and is_binary(b) and byte_size(a) + byte_size(b) < 64 do
    Kernel.<>(a, b)
  end

  def concat(a, b) do
    raise "can only <> binaries with a combined size below 64"
  end

  # defmacro concat_ do

  # defmacro a <|> b when is_binary(a) do
  #   quote do
  #     Kernel.<>(a, b) when byte_size(b) < 64
  #   end
  # end

  def access_get(%{} = map, k) do
    Map.get(map, k)
  end

  def access_get(l, k) when is_list(l) do
    Keyword.get(l, k)
  end
end
