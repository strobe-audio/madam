defmodule Madam.AnnouncerTest do
  use ExUnit.Case, async: false

  alias Madam.DNS

  @local_addr Madam.private_ips() |> hd()

  @qu_addr @local_addr
           |> then(fn {a, b, c, d} -> {a, b, c, max(1, Integer.mod(d + 1, 255))} end)
           |> IO.inspect()

  @question %DNS.Msg{
    addr: @qu_addr,
    answers: [],
    opcode: :query,
    qr: false,
    questions: [%DNS.RR{class: :in, domain: "_hap._tcp.local", type: :ptr}],
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

    IO.inspect(broadcast: msg)

    assert msg.answers == [
             %Madam.DNS.RR{
               class: :in,
               data: 'My service._hap._tcp.local.',
               domain: '_hap._tcp.local.',
               ttl: 120,
               type: :ptr
             }
           ]

    assert msg.questions == [
             %Madam.DNS.RR{
               class: :in,
               data: nil,
               domain: "_hap._tcp.local",
               ttl: nil,
               type: :ptr
             }
           ]

    for ip <- Madam.response_ips(@qu_addr) do
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
             domain: 'My service._hap._tcp.local.',
             ttl: 120,
             type: :srv
           } = Enum.find(msg.resources, fn r -> r.type == :srv end)

    # assert service == %Madam.Service{
    #          addrs: [{192, 168, 1, 152}],
    #          data: %{
    #            "c#" => "189",
    #            "ci" => "2",
    #            "ff" => "1",
    #            "id" => "C9:D4:73:0C:86:6A",
    #            "md" => "TRADFRI gateway",
    #            "pv" => "1.1",
    #            "s#" => "541",
    #            "sf" => "0",
    #            "sh" => "xn3qeA=="
    #          },
    #          domain: "_hap._tcp.local",
    #          hostname: "TRADFRI-Gateway-b072bf25d7e3.local",
    #          name: "TRADFRI gateway",
    #          port: 80,
    #          priority: 0,
    #          protocol: :tcp,
    #          service: "hap",
    #          ttl: 4500,
    #          weight: 0
    #        }
  end
end
