defmodule Please do
  @moduledoc """
  Documentation for `Please`.

  This module will handle requests from nodes in the network and route them to
  the correct node that can handle the request. The module will also keep track
  of the nodes in the network and their capabilities to handle requests.
  """
  use Supervisor

  def start_link(init_arg \\ []),
    do: Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)

  @impl true
  def init(opts \\ []) do
    children = [
      {Please.Nodes, Keyword.get(opts, :nodes, [])},
      {Please.Requests, Keyword.get(opts, :requests, [])},
      {Please.Nodes.PingTask, Keyword.get(opts, :ping, [])},
      {Please.Nodes.SyncTask, Keyword.get(opts, :sync, [])},
      {Please.Requests.AssignRequestsTask, Keyword.get(opts, :assign_requests, [])},
      {Please.Requests.HandleRequestsTask, Keyword.get(opts, :handle_requests, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defmacro __using__(_) do
    quote do
      require Please
    end
  end

  @doc """
  Makes a request to the network. The default timeout is 5000 milliseconds and
  can be changed by passing the `timeout` option.

  ## Examples

      iex> Please.make_it_so(MyModule, :my_function, [1, 2, 3])
      {:ok, function_output, :"some@other.node"}

  """
  @spec make_it_so(atom, atom, list, list) :: {:ok, any, atom} | {:error, :timeout}
  defmacro make_it_so(module, function, args \\ [], opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)

    quote do
      Task.async(fn ->
        request =
          %{id: id} =
          Please.Requests.Request.new(self(), unquote(module), unquote(function), unquote(args))

        Please.Requests.add(request)

        receive do
          {Please.Requests, :response, ^id, remitent, result} -> {:ok, result, remitent}
        after
          unquote(timeout) -> {:error, :timeout}
        end
      end)
      |> Task.await()
    end
  end
end
