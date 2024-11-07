defmodule Please.Nodes.PingTask do
  @moduledoc """
  A task that pings the node network.

  This task will ping the nodes in the network and update the state of the
  agent with the nodes that are reachable. The task will also update the state
  of the agent with the metadata of the nodes that are reachable.

  The ping latency can be configured with the `:latency` option of the `:ping`
  key in the application configuration (in milliseconds), the default is 1500
  milliseconds.
  """
  use Task

  alias Please.Nodes

  @persistence_file "priv/please/persisted_nodes.dat"

  @doc false
  def start_link(opts \\ []),
    do:
      Task.start_link(
        __MODULE__,
        :run,
        [Keyword.put(opts, :persisted_nodes, maybe_read_from_disk())]
      )

  @doc false
  def run(opts \\ []) do
    persisted_nodes = Keyword.get(opts, :persisted_nodes, [])

    Agent.get_and_update(Please.Nodes, fn {self_node, state} ->
      nodes =
        Enum.uniq(((persisted_nodes ++ Map.keys(state)) -- [self_node]) ++ Nodes.referrals())

      metadata = Nodes.metadata()

      state =
        Enum.reduce(nodes, [], fn node, acc ->
          case Node.ping(node) do
            :pong ->
              [node | acc]

            _ ->
              acc
          end
        end)
        |> Enum.map(&{&1, state[&1] || Nodes.rpc(&1, Please.Nodes, :metadata, [])})
        |> Map.new()

      Enum.each(Map.keys(state), fn node ->
        spawn(fn ->
          Agent.cast(
            {Please.Nodes, node},
            &{elem(&1, 0), Map.put(elem(&1, 1), self_node, metadata)}
          )
        end)
      end)

      {nodes, {self_node, Map.put(state, self_node, metadata)}}
    end)
    |> Enum.sort()
    |> maybe_write_to_disk(persisted_nodes)

    opts =
      opts
      |> Keyword.put(:persisted_nodes, persisted_nodes)
      |> Keyword.put_new(:latency, 1500)

    :timer.sleep(opts[:latency])

    run(opts)
  end

  defp maybe_write_to_disk(nodes, nodes),
    do: nodes

  defp maybe_write_to_disk(nodes, _persisted_nodes) do
    File.mkdir_p(Path.dirname(@persistence_file))
    File.write(@persistence_file, :erlang.term_to_binary(nodes))
    nodes
  end

  defp maybe_read_from_disk() do
    case File.read(@persistence_file) do
      {:ok, content} ->
        case :erlang.binary_to_term(content) do
          {:ok, nodes} ->
            nodes

          _ ->
            []
        end

      {:error, _} ->
        []
    end
  end
end
