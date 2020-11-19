# import Kernel, only: [defmodule: 2, defmacro: 2, if: 2, in: 2]

# defmodule Sand.SafeUnreserved do
#   for x <- Sand.safe_binary do
#     defmacro unquote(:"#{Sand.prefix}#{x}")(arg1, arg2) do
#       y = unquote(x)
#       quote do
#         unquote(y)(unquote(arg1), unquote(arg2))
#       end
#     end
#   end
#   for x <- Sand.safe_unary do
#     defmacro unquote(:"#{Sand.prefix}#{x}")(arg) do
#       y = unquote(x)
#       quote do
#         unquote(y)(unquote(arg))
#       end
#     end
#   end
# end
