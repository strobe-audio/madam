# defmodule Madam.Client.Supervisor do
#   @moduledoc false

#   use DynamicSupervisor

#   def start_link(arg) do
#     DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
#   end

#   def resolve(service, from) do
#     DynamicSupervisor.start_child(__MODULE__, {Madam.Client.Resolver, {service, from}})
#   end

#   @impl true
#   def init(_arg) do
#     DynamicSupervisor.init(strategy: :one_for_one)
#   end
# end
