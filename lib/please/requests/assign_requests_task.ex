defmodule Please.Requests.AssignRequestsTask do
  @moduledoc """
  A task that assigns requests around the node network based on busyness and
  acceptance priority of each node.

  This task will run periodically and will assign requests to the nodes in the
  network by checking the acceptance priority of each task for each node.

  The asignation latency can be configured with the `:latency` option of the
  `:assign_requests` key in the application configuration (in milliseconds),
  the default is 20 milliseconds.
  """
  use Task

  alias Please.Requests

  @doc false
  def start_link(opts \\ []),
    do: Task.start_link(__MODULE__, :run, opts)

  @doc false
  def run(opts \\ []) do
    nodes = Map.keys(Please.Nodes.get())

    Enum.each(Requests.get_pending(), fn request ->
      preferable_node =
        nodes
        |> Enum.map(&{&1, Requests.acceptance_priority(&1, request)})
        |> Enum.reject(&is_nil(elem(&1, 1)))
        |> Enum.max_by(&elem(&1, 1))
        |> elem(0)

      if preferable_node == Node.self(),
        do: Requests.pick(request),
        else: Requests.delegate(preferable_node, request)
    end)

    :timer.sleep(Keyword.get(opts, :latency, 20))

    run(opts)
  end
end
