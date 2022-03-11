defmodule Madam.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: Madam.Service.Registry},
      {Registry, keys: :unique, name: Madam.Interface.Registry},
      Madam.Listener,
      Madam.UDP.Supervisor,
      Madam.Service.Supervisor
      # {Madam.Service,
      #  service: [
      #    name: "Madam",
      #    port: 9999,
      #    service: "madam"
      #  ]}
    ]

    opts = [strategy: :one_for_one, name: Madam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
