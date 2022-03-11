defmodule Madam.Listener do
  use GenServer

  alias Madam.{DNS, Service}

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
    Logger.warn(fn -> ["QUERY ", inspect(service)] end)

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

  defp handle_msg(%Madam.DNS.Msg{answers: []} = msg, state) do
    %{questions: questions} = msg
    # IO.inspect(question: questions)

    ptrs = Enum.filter(questions, fn q -> q.type == :ptr end)

    enumeration = Enum.find(ptrs, fn p -> p.domain == "_services._dns-sd._udp.local" end)

    if enumeration do
      IO.inspect(:ENUMERATE____________________)

      spec = [
        # match
        {{:srv, :_}, :"$1", :_},
        # guards
        [],
        # body
        [:"$1"]
      ]

      # all keys
      spec = [{{{:"$1", :"$2"}, :_, :_}, [], [:"$1", :"$2"]}]

      IO.inspect(Registry.select(Madam.Service.Registry, spec), label: :pids)
    else
      for ptr <- ptrs do
        Registry.dispatch(Madam.Service.Registry, {:srv, ptr.domain}, fn entries ->
          # service = Madam.Service.from_dns(msg)
          # Logger.info(fn -> [" of service ", inspect(service)] end)

          for {pid, _opts} <- entries, do: send(pid, {Madam, :query, msg})
        end)
      end
    end

    state
  end

  defp handle_msg(msg, state) do
    state
  end

  @s %Madam.DNS.Msg{
    addr: {192, 168, 1, 72},
    answers: [
      %Madam.DNS.RR{
        class: :in,
        data: "TRADFRI gateway._hap._tcp.local",
        domain: "_hap._tcp.local",
        ttl: 4497,
        type: :ptr
      }
    ],
    opcode: :query,
    qr: false,
    questions: [
      %Madam.DNS.RR{class: :in, data: nil, domain: "lb._dns-sd._udp.local", ttl: nil, type: :ptr},
      %Madam.DNS.RR{class: :in, data: nil, domain: "_hap._tcp.local", ttl: nil, type: :ptr},
      %Madam.DNS.RR{class: :in, data: nil, domain: "_hap._udp.local", ttl: nil, type: :ptr},
      %Madam.DNS.RR{class: :in, data: nil, domain: "_homekit._tcp.local", ttl: nil, type: :ptr},
      %Madam.DNS.RR{
        class: :in,
        data: nil,
        domain: "_companion-link._tcp.local",
        ttl: nil,
        type: :ptr
      },
      %Madam.DNS.RR{class: :in, data: nil, domain: "_airplay._tcp.local", ttl: nil, type: :ptr},
      %Madam.DNS.RR{class: :in, data: nil, domain: "_raop._tcp.local", ttl: nil, type: :ptr},
      %Madam.DNS.RR{
        class: :in,
        data: nil,
        domain: "_sleep-proxy._udp.local",
        ttl: nil,
        type: :ptr
      }
    ],
    resources: [
      %Madam.DNS.RR{
        class: :in,
        data: <<0, 4, 0, 14, 0, 155, 250, 195, 204, 189, 81, 56, 238, 156, 136, 64, 62, 39>>,
        domain: ".",
        ttl: nil,
        type: :opt
      }
    ],
    type: :msg
  }

  @airdrop %Madam.DNS.Msg{
    addr: {192, 168, 1, 118},
    answers: [
      %Madam.DNS.RR{
        class: :in,
        # instance_name
        data: "f875181beedf._airdrop._tcp.local",
        # service_domain
        domain: "_airdrop._tcp.local",
        ttl: 4500,
        type: :ptr
      }
    ],
    opcode: :query,
    qr: true,
    questions: [],
    resources: [
      %Madam.DNS.RR{
        class: :in,
        # hostname
        data: {0, 0, 8770, 'bd8d625c-fd9e-4099-bc99-a900756424c3.local'},
        # instance_name
        domain: "f875181beedf._airdrop._tcp.local",
        ttl: 120,
        type: :srv
      },
      %Madam.DNS.RR{
        class: :in,
        data: {65152, 0, 0, 0, 5166, 25703, 61080, 47351},
        # hostname
        domain: "bd8d625c-fd9e-4099-bc99-a900756424c3.local",
        ttl: 120,
        type: :aaaa
      },
      %Madam.DNS.RR{
        class: :in,
        data: {192, 168, 1, 118},
        # hostname
        domain: "bd8d625c-fd9e-4099-bc99-a900756424c3.local",
        ttl: 120,
        type: :a
      },
      %Madam.DNS.RR{
        class: :in,
        data: {10752, 9159, 50304, 23809, 6386, 40791, 11877, 57022},
        # hostname
        domain: "bd8d625c-fd9e-4099-bc99-a900756424c3.local",
        ttl: 120,
        type: :aaaa
      },
      %Madam.DNS.RR{
        class: :in,
        data: ["flags=1019"],
        # instance_name
        domain: "f875181beedf._airdrop._tcp.local",
        ttl: 4500,
        type: :txt
      },
      %Madam.DNS.RR{
        class: :in,
        data: <<192, 43, 0, 5, 0, 0, 128, 0, 64>>,
        # instance_name
        domain: "f875181beedf._airdrop._tcp.local",
        ttl: 120,
        type: 47
      },
      %Madam.DNS.RR{
        class: :in,
        data: <<192, 76, 0, 4, 64, 0, 0, 8>>,
        # hostname
        domain: "bd8d625c-fd9e-4099-bc99-a900756424c3.local",
        ttl: 120,
        type: 47
      }
    ],
    type: :msg
  }
end
