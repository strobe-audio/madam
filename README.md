# Madam

Services offered...

```elixir
def deps do
  [
    {:madam, "~> 0.1.0"}
  ]
end
```

## Server

``` elixir
# advertise the "_ssh._tcp.local" service

service = %Madam.Service{
  # required information
  name: "My service instance name",
  port: 22,
  service: "ssh",

  # optional data for service consumers
  data: %{
    someFlag: true,
    someValue: "present"
  },

  # defaults 
  protocol: :tcp,
  domain: "local",
  ttl: 120,
  weight: 10,
  priority: 10
}

# run as part of your application's supervision tree

defmodule MyApplication.Application do
  use Application

  def start(_type, _args) do
    service = Madam.Service{
      # ...
    }

    children = [
      {Madam.Service, service: service}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApplication.Supervisor)
  end
end


# advertise an ad-hoc service

Madam.advertise(service)

```

## Client

``` elixir


# receive notifications of services being offered
# this should be run from a process (`GenServer`)
# which will receive messages when a new instance
# appears on the local network


# default protocol is `:tcp` so this will 
defmodule Subscriber do
  use GenServer
  
  # ...

  def init(_) do
    Madam.subscribe("ssh")
    {:ok, []}
  end
  
  def handle_info({Madam, :announce, %Madam.Service{} = service}, state) do
    # do something with the new service
    state = handle_service(service, state)

    {:noreply, state}
  end
end

```

