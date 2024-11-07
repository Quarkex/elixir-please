defmodule Please.Requests.Request do
  @moduledoc """
  A struct to represent a single request from some node.

  The `id` field is a UUID acting as an unique identifier for the request. The
  `node` field is the atom node name of the node that sent the request and
  hosts the PID of the process that the request response will be sent to.
  """
  @type t :: %__MODULE__{
          id: String.t(),
          node: atom(),
          pid: pid(),
          module: atom(),
          function: atom(),
          args: list()
        }

  defstruct [:id, :node, :pid, :module, :function, :args]

  @doc """
  Create a new request struct. The `from` field will be the atom node name of
  the current node, and the `id` field will be a new UUID.

  ## Examples

      iex> Please.Request.new(Node, :self)
      %Please.Request{id: <some uuid>, from: :nonode@nohost, to: nil, module: Node, function: :self, args: []}

  """
  def new(pid, module, function, args \\ [])
      when is_atom(module) and is_atom(function) and is_list(args),
      do: %__MODULE__{
        id: UUID.uuid4(),
        node: Node.self(),
        pid: pid,
        module: module,
        function: function,
        args: args
      }
end
