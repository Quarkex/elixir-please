defmodule Please.Nodes do
  @moduledoc """
  An agent listing nodes in the network and the requests they can handle. It
  also keeps track of the busyness of the current node and it's name.

  The `key` is the atom node name of the node. The `value` must be a metadata
  map.

  This dictionary is built from remote nodes that are connected to the network,
  and will be stored in a map handled in this module acting as an Agent.
  """
  use Agent

  @doc """
  Make a remote procedure call to a node.

  This function will call a function of a module in the given node with
  optional arguments.
  """
  @spec rpc(atom, atom, atom, list) :: {:ok, any} | {:error, any}
  def rpc(node, module, function, args \\ [])
      when is_atom(node) and is_atom(module) and is_atom(function) and is_list(args) do
    case :rpc.call(node, Module.concat([Elixir, module]), function, args) do
      {:badrpc, {:EXIT, {reason, _metadata}}} ->
        {:error, reason}

      {:badrpc, _} ->
        {:error, :badrpc}

      response ->
        {:ok, response}
    end
  end

  @doc """
  Get the referrals from the configuration.

  The referrals are a comma-separated list of atoms that represent the nodes
  that are connected to the network. This list is used to build the initial
  state of the agent, filtering out the nodes that are not reachable.
  """
  @spec referrals() :: map
  def referrals() do
    case Application.get_env(:please, :referrals) do
      nil ->
        []

      string ->
        String.split(string, ",", trim: true)
        |> Enum.reject(&(&1 == "" || &1 == nil))
        |> Enum.map(&String.to_atom/1)
    end
  end

  def metadata(),
    do: Application.get_env(:please, :metadata) || %{}

  @doc """
  Start the agent.
  """
  @spec start_link(any) :: {:ok, pid}
  def start_link(_opts) do
    state = Map.put(%{}, Node.self(), metadata())

    Agent.start_link(fn -> {Node.self(), state} end, name: __MODULE__)
  end

  @doc """
  Get the metadata of all nodes.
  """
  @spec get() :: map
  def(get, do: Agent.get(__MODULE__, &elem(&1, 1)))

  @doc """
  Get the metadata of a node.
  """
  @spec get(atom) :: map | nil
  def get(node_atom) when is_atom(node_atom),
    do: Agent.get(__MODULE__, &Map.get(elem(&1, 1), node_atom))

  @doc """
  Set the node metadata
  """
  @spec set(atom, map) :: :ok
  def set(node_atom, map) when is_atom(node_atom) and is_map(map),
    do: Agent.update(__MODULE__, &{elem(&1, 0), Map.put(elem(&1, 1), node_atom, map)})

  @doc """
  Set this node metadata
  """
  @spec set(map) :: :ok
  def set(map) when is_map(map),
    do:
      Agent.update(
        __MODULE__,
        &{elem(&1, 0), Map.put(elem(&1, 1), elem(&1, 0), map)}
      )
end
