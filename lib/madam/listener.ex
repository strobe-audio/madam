defmodule Madam.Listener do
  use GenServer

  alias Madam.DNS

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def subscribe(service) when is_binary(service) do
    Registry.register(Madam.Service.Registry, {:ptr, service}, [])
    GenServer.cast(__MODULE__, {:query, service})
  end

  def notify(msg) do
    GenServer.cast(__MODULE__, {:notify, msg})
  end

  def init(_args) do
    {:ok, %{}}
  end

  def handle_cast({:notify, msg}, state) do
    Logger.debug(fn -> ["DNS msg ", inspect(msg)] end)
    handle_msg(msg, state)
    {:noreply, state}
  end

  def handle_cast({:query, service}, state) do
    Logger.info(fn -> ["QUERY ", inspect(service)] end)

    msg = %DNS.Msg{
      questions: [
        %DNS.Query{type: :ptr, domain: service}
      ],
      opcode: :query,
      aa: false,
      qr: false
    }

    Madam.UDP.broadcast(msg)

    {:noreply, state}
  end

  defp handle_msg(%Madam.DNS.Msg{questions: []} = msg, state) do
    ptr = Enum.find(msg.answers, fn a -> a.type == :ptr end)

    case ptr do
      %{domain: domain} ->
        Registry.dispatch(Madam.Service.Registry, {:ptr, domain}, fn entries ->
          service = Madam.Service.from_dns(msg)
          Logger.info(fn -> ["Notifying of service ", inspect(service)] end)

          for {pid, _opts} <- entries, do: send(pid, {Madam, :announce, service})
        end)

      _none ->
        :ok
    end

    state
  end

  defp handle_msg(%Madam.DNS.Msg{} = msg, state) do
    %{questions: questions} = msg

    {enumeration, ptrs} =
      questions
      |> Enum.filter(fn q -> q.type == :ptr end)
      |> Enum.split_with(fn p -> p.domain == "_services._dns-sd._udp.local" end)

    case enumeration do
      [_query | _] ->
        Logger.debug(fn ->
          ["Request for service enumeration via _services._dns-sd._udp.local"]
        end)

        all_services()

      [] ->
        []
    end
    |> Enum.each(&send_query(&1, :ptr, msg))

    for ptr <- ptrs do
      Registry.dispatch(Madam.Service.Registry, {:srv, ptr.domain}, fn entries ->
        entries
        |> Enum.map(&elem(&1, 0))
        |> Enum.each(&send_query(&1, :ptr, msg))
      end)
    end

    aa =
      questions
      |> Enum.filter(fn q -> q.type == :a end)

    for q <- aa do
      Registry.dispatch(Madam.Service.Registry, {:a, q.domain}, fn entries ->
        entries
        |> Enum.map(&elem(&1, 0))
        |> Enum.each(&send_query(&1, :a, msg))
      end)
    end

    state
  end

  defp handle_msg(msg, state) do
    Logger.warning(fn -> ["Unhandled msg ", inspect(msg)] end)
    state
  end

  defp all_services() do
    Madam.services()
    |> Enum.map(& &1.pid)
  end

  defp send_query(pid, type, msg) do
    Logger.info(fn -> ["Query received for service ", inspect(msg.questions)] end)
    send(pid, {Madam, {:query, type}, msg})
  end
end
