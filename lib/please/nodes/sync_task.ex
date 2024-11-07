defmodule Please.Nodes.SyncTask do
  @moduledoc """
  A task that sync the node list across the network.

  This task will sync the nodes in the network and update the state of the
  agent with the nodes that are reachable.

  The sync latency can be configured with the `:latency` option of the `:sync`
  key in the application configuration (in milliseconds), the default is 3000
  milliseconds.
  """
  use Task

  alias Please.Nodes

  @doc false
  def start_link(opts \\ []),
    do: Task.start_link(__MODULE__, :run, [opts])

  @doc false
  def run(opts \\ []) do
    with %{} = current_nodes <- Nodes.get() do
      updated_node_list =
        (Map.keys(current_nodes) -- [Node.self()])
        |> Enum.reduce(%{}, fn node, acc ->
          case Node.ping(node) do
            :pong ->
              with {:ok, %{} = new_nodes} <- Nodes.rpc(node, Please.Nodes, :get) do
                Map.merge(acc, new_nodes)
              else
                _ ->
                  acc
              end

            _ ->
              acc
          end
        end)
        |> Map.put(Node.self(), Nodes.metadata())

      Agent.cast(Please.Nodes, fn _old_state -> {Node.self(), updated_node_list} end)
    end

    :timer.sleep(Keyword.get(opts, :latency, 3000))

    run(opts)
  end
end
