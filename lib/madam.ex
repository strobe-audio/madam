defmodule Madam do
  def subscribe(service, opts \\ []) do
    protocol = Keyword.get(opts, :protocol, :tcp)

    domain = Madam.Service.service_domain(service, protocol, "local")

    Madam.Listener.subscribe(domain)
  end

  def services do
    spec = [{{{:srv, :"$1"}, :"$2", :_}, [], [%{domain: :"$1", pid: :"$2"}]}]

    Registry.select(Madam.Service.Registry, spec)
  end
end
