# Please

"Oh, I get by with a little help from my friends"

Please is a simple Elixir library that provides a way to seamesly balance
requests across multiple Elixir nodes. It is designed to be used in a
distributed system where multiple nodes are available to handle requests.
Please will automatically distribute requests across all available nodes taking
into account the amount and weight of the requests each node is currently
handling, and if the nodes can handle the task at all.

## Usage

First, you need to start the Please application on all nodes that you want to
balance requests across. To do so you may include it in your `mix.exs` file:

```elixir
def application do
  [
    extra_applications: [:please]
  ]
end
```

Then, use `Please` in your module to be able to make requests to the node
network.

```elixir
defmodule MyModule do
  use Please

  def my_function do
    Please.make_it_so(SomeOtherModule, :some_other_function, [:some_arg, :some_other_arg, ...])
    #=> {:ok, result, remitent_node} || {:error, :timeout}
  end
end
```

The application will handle node list persistence, node availability, and
request balancing for you. You just need to call `Please.make_it_so` with the
module and function you want to call, and optionally the arguments you want to
pass to it. If a node has such a combination of module, function and arity, it
will be elegible to handle the request, and the one with the least amount of
workload (based on requests currently being handled) will be chosen to handle
it.

## Configuration

Please can be configured to always try to connect to a coma-separated list of
nodes. This referral list can be set in the config files of your application:

```elixir
config :please,
  referrals: "node1@localhost,node2@localhost"
```

It's possible to define a metadata map that will be sent to the nodes to keep
in the node list. This metadata can be freely specified, but is only updated
once at connection time. The metadata can be set in the config files of your
application:

```elixir
config :please,
  metadata: %{"my_key" => "my_value"}
```

The weight and offset of specific modules and functions can also be configured
in the config files of your application:

```elixir
config :please,
  busyness_weights: %{
    MyModule: %{my_function: 200}
  },
  busyness_offset: %{
    MyModule: %{my_function: -50}
  }
```

The offset represent how eager a node is to handle a request. A negative offset
will make the node more likely to be chosen to handle a request, while a
positive offset will make it less likely. The weight represents how much work a
request will be for the node. The higher the weight, the less likely the node
will be chosen to handle the request if it is handling such a task.

Any unspecified combination of module and function that is defined in the node
will have a default weight of 100 and a default offset of 0. The weight and
offset is used to calculate the busyness of a node by adding the total weight
of requests currently being handled by the node and then adding the offset. If
the custom weight is set to `:reject`, the node will be considered ineligible
to handle the request even if it has the module and function available.

For further configuration options, please refer to the documentation of each
module in the `Please` namespace.

## A word of caution

Such friendship requires a lot of trust. The erlang distribution protocol is
not secure, and the nodes will trust each other blindly. Please make sure that
you trust all nodes in your network AND the network itself, and that you have
taken the necessary precautions to secure your network traffic.

A good practice is to use a VPN to secure the communication between nodes, and
to use a firewall to restrict the access to the nodes to only the necessary
ports.

## Installation

It's [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `please` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:please, "~> 0.1.0"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/please>.

