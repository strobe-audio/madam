defmodule Madam.AnnouncerTest do
  use ExUnit.Case, async: false

  alias Madam.DNS

  # construct a dns question that appears to come from a network interface we're listening on,
  # from some other server on that network
  {:ok, [{ifname, addrs} | _]} = Madam.Network.interfaces()

  @local_ifname ifname
  @local_addr addrs

  @qu_addr @local_addr
           |> hd()
           |> then(fn {a, b, c, d} -> {a, b, c, max(1, Integer.mod(d + 1, 255))} end)

  @question %DNS.Msg{
    ifaddr: @local_addr,
    ifname: @local_ifname,
    addr: @qu_addr,
    answers: [],
    opcode: :query,
    qr: false,
    questions: [%DNS.Query{class: :in, domain: "_hap._tcp.local", type: :ptr}],
    resources: [],
    type: :msg
  }

  defmodule Watcher do
    use GenServer

    def start_link(args) do
      GenServer.start_link(__MODULE__, args)
    end

    def init(args) do
      {:ok, parent} = Keyword.fetch(args, :parent)
      {:ok, domain} = Keyword.fetch(args, :domain)
      Madam.subscribe(domain)
      {:ok, {domain, parent}}
    end

    def handle_info({Madam, :announce, service}, {domain, parent}) do
      send(parent, {:announce, service})

      {:noreply, {domain, parent}}
    end
  end

  defmodule UDPMonitor do
    def broadcast(msg, opts \\ []) do
      {:ok, parent} = Keyword.fetch(opts, :parent)
      send(parent, {:broadcast, msg})
    end
  end

  test "notifies listeners of service advertisement" do
    {:ok, _pid} = start_supervised({Watcher, domain: "hap", parent: self()})

    start_supervised(
      {Madam.Announcer,
       service: [name: "My service", port: 1033, service: "hap", data: %{something: "here"}],
       udp: {UDPMonitor, [[parent: self()]]}}
    )

    Madam.Listener.notify(@question)

    assert_receive {:broadcast, msg}

    assert msg.answers == [
             %Madam.DNS.RR{
               class: :in,
               data: 'My service._hap._tcp.local',
               domain: '_hap._tcp.local',
               ttl: 120,
               type: :ptr
             }
           ]

    assert msg.questions == []

    for ip <- Madam.Network.response_ips(@qu_addr) do
      assert Enum.find(msg.resources, fn r -> r.type == :a and r.data == ip end)
    end

    assert Enum.find(msg.resources, fn r -> r.type == :txt end) == %Madam.DNS.RR{
             class: :in,
             data: ['something=here'],
             domain: 'My service._hap._tcp.local',
             ttl: 120,
             type: :txt
           }

    # use a match because the hostname is auto-generated
    assert %Madam.DNS.RR{
             class: :in,
             data: {10, 10, 1033, 'hap-1033-' ++ _},
             domain: 'My service._hap._tcp.local',
             ttl: 120,
             type: :srv
           } = Enum.find(msg.resources, fn r -> r.type == :srv end)
  end
end
