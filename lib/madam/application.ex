defmodule Madam.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    IO.inspect(__MODULE__)

    children = [
      {Registry, keys: :duplicate, name: Madam.Service.Registry},
      {Registry, keys: :unique, name: Madam.Interface.Registry},
      Madam.Listener,
      Madam.UDP.Supervisor
      # {Madam.Advertise, []},
      # Madam.Service.Supervisor,
      # # just a dummy service to test things
      # {Madam.Announcer,
      #  service: [
      #    name: "This is XXX. Fish",
      #    port: 1033,
      #    service: "erlang",
      #    data: [:someFlag, this: "that"]
      #  ]}
      # Madam.Client,
      # Madam.Client.Supervisor,
      # Madam.Receiver
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Madam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
