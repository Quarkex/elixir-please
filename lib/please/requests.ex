defmodule Please.Requests do
  @moduledoc """
  An agent listing all requests that have been made to the network.

  The first list holds the requests that this node is asking to be resolved,
  while the second list holds the requests that this node is resolving itself.

  It's possible to request the busyness of another node in relation to
  performing a certain request. The other node should return an integer with
  the priority of the node to handle the request (with any offset applied) or
  nil if the node simply cannot handle the request in any way.

  Nodes handle their own busyness level, which increases or decreases as they
  accept and finish requests. It is possible to configure the node in such a
  way that certain requests alter the busyness level of the node in varying
  levels. This way, the node can be configured to prefer certain types of
  requests over others.

  """
  use Agent

  alias Please.Requests.Request

  @doc """
  Start the agent.
  """
  @spec start_link(any) :: {:ok, pid}
  def start_link(_opts),
    do: Agent.start_link(fn -> {[], [], 0} end, name: __MODULE__)

  @doc """
  Add a request.
  """
  @spec add(Request.t()) :: :ok | :error
  def add(%Request{} = request) do
    Agent.update(__MODULE__, fn {pending_requests, handling_requests, base_busyness} ->
      pending_requests = Enum.reject(pending_requests, &(&1.id == request.id))
      {[request | pending_requests], handling_requests, base_busyness}
    end)
  end

  @doc """
  Remove a request.
  """
  @spec remove(Request.t() | String.t()) :: :ok | :error
  def remove(%Request{id: request_id}) when not is_nil(request_id),
    do: remove(request_id)

  def remove(request_id) when is_bitstring(request_id) do
    Agent.update(__MODULE__, fn {pending_requests, handling_requests, base_busyness} ->
      {
        Enum.reject(pending_requests, &(&1.id == request_id)),
        Enum.reject(handling_requests, &(&1.id == request_id)),
        base_busyness
      }
    end)
  end

  @doc """
  Pick a request to be handled.
  """
  @spec pick(Request.t() | String.t()) :: :ok | :error
  def pick(request_id) when is_bitstring(request_id) do
    Agent.update(__MODULE__, fn {pending_requests, handling_requests, base_busyness} ->
      case Enum.find(pending_requests, &(&1.id == request_id)) do
        nil ->
          raise ArgumentError, "Request `#{request_id}` not found"
          {pending_requests, handling_requests, base_busyness}

        request ->
          {
            Enum.reject(pending_requests, &(&1.id == request_id)),
            [request | Enum.reject(handling_requests, &(&1.id == request_id))],
            base_busyness
          }
      end
    end)
  end

  def pick(%Request{id: request_id} = request) when not is_nil(request_id) do
    Agent.update(__MODULE__, fn {pending_requests, handling_requests, base_busyness} ->
      {
        Enum.reject(pending_requests, &(&1.id == request_id)),
        [request | Enum.reject(handling_requests, &(&1.id == request_id))],
        base_busyness
      }
    end)
  end

  @doc """
  Delegate a request to another node.
  """
  @spec delegate(atom, Request.t() | String.t()) :: :ok | :error
  def delegate(node, request_id) when is_atom(node) and is_bitstring(request_id) do
    case get(request_id) do
      nil ->
        raise ArgumentError, "Request `#{request_id}` not found"
        :error

      request ->
        delegate(node, request)
    end
  end

  def delegate(node, %Request{id: request_id} = request)
      when is_atom(node) and not is_nil(request_id) do
    Agent.update(__MODULE__, fn {pending_requests, handling_requests, base_busyness} ->
      Agent.update({__MODULE__, node}, fn {remote_pending_requests, remote_handling_requests,
                                           remote_base_busyness} ->
        {
          Enum.reject(remote_pending_requests, &(&1.id == request_id)),
          [request | Enum.reject(remote_handling_requests, &(&1.id == request_id))],
          remote_base_busyness
        }
      end)

      {
        Enum.reject(pending_requests, &(&1.id == request_id)),
        Enum.reject(handling_requests, &(&1.id == request_id)),
        base_busyness
      }
    end)
  end

  @doc """
  Handle a request, returning the output to the requester PID.

  The requester will receive a tuple with the module name, the function name,
  the ID of the request, and the output of the function call, inside a tuple.

  If the function call raises an error, the requester will receive a tuple with
  the module name, the atom `:error` name, the request itself, and the error
  message, inside a tuple.
  """
  @spec handle(Request.t() | String.t()) :: :ok | :error
  def handle(request_id) when is_bitstring(request_id) do
    case get(request_id) do
      nil ->
        raise ArgumentError, "Request `#{request_id}` not found"
        :error

      request ->
        handle(request)
    end
  end

  def handle(%Request{} = request) do
    if request.node == Node.self() do
      spawn(fn ->
        try do
          output = apply(request.module, request.function, request.args)
          send(request.pid, {__MODULE__, :response, request.id, Node.self(), output})
        rescue
          error ->
            send(request.pid, {__MODULE__, :error, request, Node.self(), error})
        end
      end)

      Agent.cast(__MODULE__, fn state ->
        {
          Enum.reject(elem(state, 0), &(&1.id == request.id)),
          Enum.reject(elem(state, 1), &(&1.id == request.id)),
          elem(state, 2)
        }
      end)
    else
      Agent.cast(__MODULE__, fn {pending_requests, handling_requests, base_busyness} ->
        spawn(fn ->
          try do
            output = apply(request.module, request.function, request.args)

            Agent.cast({__MODULE__, request.node}, fn state ->
              send(request.pid, {__MODULE__, :response, request.id, Node.self(), output})

              {
                Enum.reject(elem(state, 0), &(&1.id == request.id)),
                Enum.reject(elem(state, 1), &(&1.id == request.id)),
                elem(state, 2)
              }
            end)
          rescue
            error ->
              send(request.pid, {__MODULE__, :error, request, Node.self(), error})

              Agent.cast({__MODULE__, request.node}, fn state ->
                {
                  Enum.reject(elem(state, 0), &(&1.id == request.id)),
                  Enum.reject(elem(state, 1), &(&1.id == request.id)),
                  elem(state, 2)
                }
              end)
          end
        end)

        {
          Enum.reject(pending_requests, &(&1.id == request.id)),
          Enum.reject(handling_requests, &(&1.id == request.id)),
          base_busyness
        }
      end)
    end
  end

  @doc """
  Get all known requests.
  """
  @spec get() :: list
  def(get, do: Agent.get(__MODULE__, &(elem(&1, 0) ++ elem(&1, 1))))

  @doc """
  Get a request by its ID.
  """
  @spec get(String.t()) :: Request.t() | nil
  def get(request_id) when is_bitstring(request_id),
    do:
      Agent.get(__MODULE__, fn {pending_requests, handling_requests, _base_busyness} ->
        Enum.find(pending_requests ++ handling_requests, &(&1.id == request_id))
      end)

  @doc """
  Get all pending requests.
  """
  @spec get_pending() :: list
  def(get_pending, do: Agent.get(__MODULE__, &elem(&1, 0)))

  @doc """
  Get a pending request by its ID.
  """
  @spec get_pending(String.t()) :: Request.t() | nil
  def get_pending(request_id) when is_bitstring(request_id),
    do:
      Agent.get(__MODULE__, fn {pending_requests, _handling_requests, _base_busyness} ->
        Enum.find(pending_requests, &(&1.id == request_id))
      end)

  @doc """
  Get all handling requests.
  """
  @spec get_handling() :: list
  def(get_handling, do: Agent.get(__MODULE__, &elem(&1, 1)))

  @doc """
  Get a handling request by its ID.
  """
  @spec get_handling(String.t()) :: Request.t() | nil
  def get_handling(request_id) when is_bitstring(request_id),
    do:
      Agent.get(__MODULE__, fn {_pending_requests, handling_requests, _base_busyness} ->
        Enum.find(handling_requests, &(&1.id == request_id))
      end)

  @doc """
  Fetch custom busyness weights for certain modules and functions.
  """
  @spec busyness_weights() :: map
  def busyness_weights(),
    do: Application.get_env(:please, :busyness_weights) || %{}

  @doc """
  Fetch the busyness weight for a request. If the weight is nil, the request
  can't be handled by the current node. It's possible to configure a rejection
  by setting the weight to `:reject`.
  """
  @spec busyness_weights(Request.t() | String.t() | nil) :: integer | nil
  def busyness_weights(%Request{module: module, function: function, args: args}) do
    if Code.ensure_loaded?(module) &&
         function_exported?(module, function, Enum.count(args)) do
      case get_in(busyness_weights(), [module, function]) do
        nil -> 100
        :reject -> nil
        weight -> weight
      end
    end
  end

  def busyness_weights(request_id) when is_bitstring(request_id),
    do: busyness_weights(get(request_id))

  def busyness_weights(nil),
    do: nil

  @doc """
  Get the acceptance priority of a given request for the current node.

  To see the documentation of the aceptance_priority function called by the agent
  itself, see the documentation of the function with the same name that takes
  two arguments.
  """
  @spec acceptance_priority(Request.t()) :: integer | nil
  def acceptance_priority(%Request{} = request),
    do: Agent.get(__MODULE__, __MODULE__, :acceptance_priority, [request])

  @doc """
  Get the acceptance priority of a given request for a specific node.

  The node can be an atom or a tuple with the node atom and the state map.

  The first case is intended to be used to request the acceptance priority of a
  node that is not the current node. The second case is intended to be the
  version of the function that is called by the agent itself when asked
  remotely, as it will have the agent state as the first argument, and the
  request as the second argument.
  """
  @spec acceptance_priority(atom | {atom, map, integer}, Request.t()) :: integer | nil
  def acceptance_priority(node, %Request{} = request) when is_atom(node),
    do: Agent.get({__MODULE__, node}, __MODULE__, :acceptance_priority, [request])

  def acceptance_priority(
        {pending_requests, handling_requests, base_busyness},
        %Request{} = request
      )
      when is_list(pending_requests) and is_list(handling_requests) and is_integer(base_busyness) do
    if Code.ensure_loaded?(request.module) &&
         function_exported?(request.module, request.function, Enum.count(request.args)) do
      case get_in(busyness_offsets(), [request.module, request.function]) do
        nil -> base_busyness * -1
        :reject -> nil
        offset -> (base_busyness + offset) * -1
      end
    end
  end

  defp busyness_offsets(),
    do: Application.get_env(:please, :busyness_offsets) || %{}

  @doc """
  Get the busyness of the local node.
  """
  @spec busyness() :: integer
  def busyness(),
    do:
      Agent.get(__MODULE__, fn {_, handling_requests, base_busyness} ->
        Enum.reduce(handling_requests, base_busyness, fn request, busyness ->
          busyness + busyness_weights(request)
        end)
      end)

  @doc """
  Get the base busyness of the local node.
  """
  @spec base_busyness() :: integer
  def(base_busyness, do: Agent.get(__MODULE__, &elem(&1, 2)))

  @doc """
  Get the base busyness of the local node.
  """
  @spec base_busyness(atom) :: integer
  def base_busyness(node) when is_atom(node),
    do: Agent.get({__MODULE__, node}, &elem(&1, 2))

  @doc """
  Increase the base busyness of the local node.
  """
  @spec base_busyness_increase(integer) :: integer
  def base_busyness_increase(amount \\ 100) when is_integer(amount),
    do:
      Agent.update(__MODULE__, fn {pending_requests, handling_requests, busyness} ->
        {pending_requests, handling_requests, busyness + amount}
      end)

  @doc """
  Decrease the base busyness of the local node.
  """
  @spec base_busyness_decrease(integer) :: integer
  def base_busyness_decrease(amount \\ 100) when is_integer(amount),
    do:
      Agent.update(__MODULE__, fn {pending_requests, handling_requests, busyness} ->
        {pending_requests, handling_requests, busyness - amount}
      end)
end
