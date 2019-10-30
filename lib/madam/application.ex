defmodule Madam.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: Madam.Service.Registry},
      {Madam.Advertise, []},
      Madam.Service.Supervisor,
      {Madam.Service, name: "This is XXX. Fish", port: 1033, service: "erlang", data: [this: "that"]},
      Madam.Client,
      Madam.Client.Supervisor,
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Madam.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
