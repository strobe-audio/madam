defmodule Madam.UDP.Supervisor do
  use Supervisor

  def name(ifname) do
    {:via, Registry, {Madam.Interface.Registry, ifname}}
  end

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    {:ok, interfaces} = Madam.Network.interfaces()

    children =
      Enum.map(interfaces, &Supervisor.child_spec({Madam.UDP, &1}, id: &1)) |> IO.inspect()

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule Madam.UDP do
  use GenServer

  alias Madam.DNS

  @callback broadcast(DNS.Msg.t(), Keyword.t()) :: :ok | {:error, term()}

  @address {224, 0, 0, 251}
  @address4 {224, 0, 0, 251}
  @port 5353
  @bind4 {0, 0, 0, 0}

  def start_link({ifname, ips}) do
    GenServer.start_link(__MODULE__, {ifname, ips}, name: Madam.UDP.Supervisor.name(ifname))
  end

  @impl __MODULE__
  def broadcast(msg, opts \\ [])

  def broadcast(%{ifname: nil} = msg, opts) do
    Madam.UDP.Supervisor
    |> Supervisor.which_children()
    |> Enum.each(fn {_, pid, :worker, _} ->
      GenServer.call(pid, {:broadcast, msg, opts})
    end)
  end

  def broadcast(%{ifname: ifname} = msg, opts) do
    ifname
    |> Madam.UDP.Supervisor.name()
    |> GenServer.call({:broadcast, msg, opts})
  end

  def list do
    Madam.UDP.Supervisor
    |> Supervisor.which_children()
    |> Enum.map(fn {_, pid, :worker, _} ->
      {:ok, address} = address(pid)
      {pid, address}
    end)
  end

  def address(pid) do
    GenServer.call(pid, :address)
  end

  @impl GenServer
  def init({ifname, addrs}) do
    {:ok, socket} = open(ifname, addrs)

    {:ok, %{socket: socket, ifname: ifname, addrs: addrs}}
  end

  @impl GenServer
  def handle_call({:broadcast, msg, _opts}, _from, state) do
    %{socket: socket} = state
    IO.inspect(udp_broadcast: msg)
    packet = DNS.encode(msg)
    result = udp_send(socket, packet)
    {:reply, result, state}
  end

  def handle_call(:address, _from, state) do
    {:reply, {:ok, %{ifname: state.ifname, ifaddrs: state.addrs}}, state}
  end

  @impl GenServer
  def handle_info({:udp, _socket, addr, _port, data}, state) do
    # IO.inspect(udp: addr, port: port)
    {:ok, record} = :inet_dns.decode(data)
    header = :inet_dns.header(:inet_dns.msg(record, :header))

    msg = %DNS.Msg{
      id: header[:id],
      type: :inet_dns.record_type(record),
      qr: header[:qr],
      opcode: header[:opcode],
      questions: questions(record),
      answers: answers(record),
      resources: resources(record),
      addr: addr,
      ifname: state.ifname,
      ifaddr: state.addrs
    }

    :ok = Madam.Listener.notify(msg)

    {:noreply, state}
  end

  # [{multicast_if, InterfaceIP},
  #  {reuseaddr, true},
  #  {multicast_ttl,4},
  #  %    {multicast_loop,false},
  #  %    {broadcast, true},
  #  {active, true},
  #  {mode, binary},
  #  {ip, MulticastIP},
  #  {add_membership,{MulticastIP, InterfaceIP}}]
  # def open(:announce) do
  #   opts = [
  #     # multicast_if: {0, 0, 0, 0},
  #     # reuseaddr: true,
  #     # multicast_ttl: 4,
  #     mode: :binary
  #     # ip: @address,
  #     # add_membership: {@address, {0, 0, 0, 0}}
  #   ]

  #   with {:ok, socket} <- open(0, opts) do
  #     {:ok, socket, @address, @port}
  #   end
  # end

  @sol_socket 0xFFFF
  @so_reuseport 0x0200
  @so_reuseaddr 0x0004

  defp open(ifname, [addr | _]) do
    udp4_options = [
      :inet,
      {:mode, :binary},
      {:reuseaddr, true},
      {:ip, @address4},
      {:multicast_if, @address4},
      {:multicast_ttl, 255},
      {:multicast_loop, true},
      {:broadcast, true},
      {:add_membership, {@address4, addr}},
      {:active, true},
      {:bind_to_device, ifname},
      {:raw, @sol_socket, @so_reuseport, <<1::native-32>>}
    ]

    :gen_udp.open(@port, udp4_options)
  end

  # defp open(port, opts) do
  #   :gen_udp.open(port, opts)
  # end

  defp udp_send(socket, msg) do
    :gen_udp.send(socket, @address4, @port, msg)
  end

  defp close(socket) do
    :gen_udp.close(socket)
  end

  defp questions(record) do
    record
    |> :inet_dns.msg(:qdlist)
    |> Enum.map(&:inet_dns.dns_query/1)
    |> Enum.map(&Enum.into(&1, %{}))
    |> Enum.map(&stringify_record/1)
    |> Enum.map(&DNS.Query.new/1)
  end

  defp answers(record) do
    rr(record, :anlist) |> Enum.map(&stringify_record/1)
  end

  defp resources(record) do
    rr(record, :arlist) |> Enum.map(&stringify_record/1)
  end

  defp rr(resources, type) do
    resources
    |> :inet_dns.msg(type)
    |> Enum.map(&:inet_dns.rr/1)
    |> Enum.map(&Enum.into(&1, []))
    |> Enum.map(&DNS.RR.new/1)
  end

  defp stringify_record(record) do
    [:data, :domain]
    |> Enum.filter(&Map.has_key?(record, &1))
    |> Enum.reduce(record, fn key, record ->
      Map.update!(record, key, fn
        [str | _] = txts when is_list(str) -> Enum.map(txts, &to_string/1)
        str when is_list(str) -> to_string(str)
        data -> data
      end)
    end)
    |> decode_ips()
  end

  defp decode_ips(%{type: type, data: ip} = record) when type in [:a, :aaaa] and is_binary(ip) do
    decoded =
      case ip do
        <<a::integer-8, b::integer-8, c::integer-8, d::integer-8>> ->
          {a, b, c, d}

        <<
          a::integer-16,
          b::integer-16,
          c::integer-16,
          d::integer-16,
          e::integer-16,
          f::integer-16,
          g::integer-16,
          h::integer-16
        >> ->
          {a, b, c, d, e, f, g, h}
      end

    %{record | data: decoded}
  end

  defp decode_ips(record) do
    record
  end
end
