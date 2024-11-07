defmodule Please.Requests.HandleRequestsTask do
  @moduledoc """
  A task that will periodically handle the requests assigned to this node.

  The handling latency can be configured with the `:latency` option of the
  `:handle_requests` key in the application configuration (in milliseconds),
  the default is 10 milliseconds.
  """
  use Task

  alias Please.Requests

  @doc false
  def start_link(opts \\ []),
    do: Task.start_link(__MODULE__, :run, opts)

  @doc false
  def run(opts \\ []) do
    Enum.each(Requests.get_handling(), &Requests.handle/1)

    :timer.sleep(Keyword.get(opts, :latency, 10))

    run(opts)
  end
end
