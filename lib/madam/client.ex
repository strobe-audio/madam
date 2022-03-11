# defmodule Madam.Client do
#   alias Madam.Service

#   use GenServer

#   def resolve(service) when is_list(service) do
#     with {:ok, _service} <- Keyword.fetch(service, :service) do
#       GenServer.call(__MODULE__, {:resolve, service})
#     else
#       :error ->
#         {:error, "service should be a keyword list containing a :service value e.g. `ssh`"}
#     end
#   end

#   def start_link(args) do
#     GenServer.start_link(__MODULE__, args, name: __MODULE__)
#   end

#   def init(_args) do
#     {:ok, %{}}
#   end

#   def handle_call({:resolve, service}, from, state) do
#     IO.inspect [__MODULE__, :handle_call]
#     Madam.Client.Supervisor.resolve(service, from)
#     {:noreply, state}
#   end
# end
