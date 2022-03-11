defmodule Madam.ListenerTest do
  use ExUnit.Case, async: false

  @msg %Madam.DNS.Msg{
    addr: {192, 168, 1, 152},
    answers: [
      %{
        class: :in,
        data: "TRADFRI gateway._hap._tcp.local",
        domain: "_hap._tcp.local",
        ttl: 4500,
        type: :ptr
      },
      %{
        class: :in,
        data: [
          "c#=189",
          "ff=1",
          "id=C9:D4:73:0C:86:6A",
          "md=TRADFRI gateway",
          "pv=1.1",
          "s#=541",
          "sf=0",
          "ci=2",
          "sh=xn3qeA=="
        ],
        domain: "TRADFRI gateway._hap._tcp.local",
        ttl: 4500,
        type: :txt
      },
      %{
        class: :in,
        data: {0, 0, 80, 'TRADFRI-Gateway-b072bf25d7e3.local'},
        domain: "TRADFRI gateway._hap._tcp.local",
        ttl: 120,
        type: :srv
      },
      %{
        class: :in,
        data: {192, 168, 1, 152},
        domain: "TRADFRI-Gateway-b072bf25d7e3.local",
        ttl: 120,
        type: :a
      },
      %{
        class: :in,
        data: {65152, 0, 0, 0, 45682, 49151, 65061, 55267},
        domain: "TRADFRI-Gateway-b072bf25d7e3.local",
        ttl: 120,
        type: :aaaa
      }
    ],
    opcode: :query,
    qr: true,
    questions: [],
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

  test "notifies listeners of service advertisement" do
    {:ok, _pid} = start_supervised({Watcher, domain: "hap", parent: self()})

    Madam.Listener.notify(@msg)

    assert_receive {:announce, service}

    assert service == %Madam.Service{
             addrs: [{192, 168, 1, 152}],
             data: %{
               "c#" => "189",
               "ci" => "2",
               "ff" => "1",
               "id" => "C9:D4:73:0C:86:6A",
               "md" => "TRADFRI gateway",
               "pv" => "1.1",
               "s#" => "541",
               "sf" => "0",
               "sh" => "xn3qeA=="
             },
             domain: "_hap._tcp.local",
             hostname: "TRADFRI-Gateway-b072bf25d7e3.local",
             name: "TRADFRI gateway",
             port: 80,
             priority: 0,
             protocol: :tcp,
             service: "hap",
             ttl: 4500,
             weight: 0
           }
  end
end
