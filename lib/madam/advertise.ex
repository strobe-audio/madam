defmodule Madam.Advertise do
  use GenServer

  @port 5353
  @address4 {224, 0, 0, 251}
  # @address6 {65282, 0, 0, 0, 0, 0, 0, 251}
  @bind4 {0, 0, 0, 0}
  # @bind6 {0, 0, 0, 0, 0, 0, 0, 0}

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def dns_send(addr, packets) when is_list(packets) do
    GenServer.call(__MODULE__, {:dns_send, addr, packets})
  end

  def init(_config) do

    udp4_options = [
      :inet,
      {:mode, :binary},
      {:reuseaddr, true},
      {:ip, @bind4},
      {:multicast_if, @address4},
      {:multicast_ttl, 4},
      {:multicast_loop, true},
      {:broadcast, true},
      {:add_membership, {@address4, @bind4}},
      {:active, true}
    ]

    # ipv6 sockets aren't supported for multicast, even in OTP22
    # https://stackoverflow.com/questions/38376640/cant-add-multicast-group

    # udp6_options = [
    #   :inet6,
    #   {:ipv6_v6only, true},
    #   {:mode, :binary},
    #   {:reuseaddr, true},
    #   {:ip, @bind6},
    #   # {:multicast_if, @address6},
    #   {:multicast_ttl, 4},
    #   {:multicast_loop, true},
    #   {:broadcast, true},
    #   # {:add_membership, {@address6, @bind6}},
    #   {:active, true}
    # ]


    {:ok, socket4} = :gen_udp.open(@port, udp4_options)
    # {:ok, socket6} = :gen_udp.open(@port, udp6_options)

    state = %{
      socket4: socket4,
      # socket6: socket6
    }
    {:ok, state}
  end

  defp send_packet(state, {}, packet) do
    :gen_udp.send(state.socket4, @address4, @port, packet)
  end

  defp send_packet(state, {address, @port}, packet) when tuple_size(address) == 4 do
    :gen_udp.send(state.socket4, @address4, @port, packet)
  end

  defp send_packet(state, {address, port}, packet) when tuple_size(address) == 4 do
    :gen_udp.send(state.socket4, address, port, packet)
  end

  # defp send_packet(state, address, @port, packet) when tuple_size(address) == 8 do
  #   :gen_udp.send(state.socket6, @address6, @port, packet)
  # end

  # defp send_packet(state, address, port, packet) when tuple_size(address) == 8 do
  #   :gen_udp.send(state.socket6, address, port, packet)
  # end

  def handle_call({:dns_send, src_address, packets}, _from, state) do
    packets
    |> Stream.map(&:inet_dns.encode/1)
    |> Enum.each(fn packet ->
      :ok = send_packet(state, src_address, packet)
    end)
    {:reply, :ok, state}
  end

  def handle_info({:udp, _socket, addr, port, data}, state) do
    {:ok, record} = :inet_dns.decode(data)
    header = :inet_dns.header(:inet_dns.msg(record, :header))
    # IO.inspect [
    #   addr: {addr, port},
    #   type: :inet_dns.record_type(record),
    #   qr: header[:qr],
    #   opcode: header[:opcode],
    #   questions: questions(record),
    #   answers: answers(record),
    #   authorities: authorities(record),
    #   resources: resources(record),
    # ]
    state = handle_record(
      {addr, port},
      :inet_dns.record_type(record),
      header[:qr],
      header[:opcode],
      questions(record),
      answers(record),
      authorities(record),
      resources(record),
      state
    )
    {:noreply, state}
  end

  defp handle_record(src_addr, :msg, false, :query, [%{domain: domain, type: type}], answers, [], [], state) do
    domain = to_string(domain)
    Registry.dispatch(Madam.Service.Registry, {type, domain}, fn entries ->
      for {pid, _opts} <- entries, do: send(pid, {:announce, type, src_addr, answers})
    end)
    state
  end

  defp handle_record(_src_addr, :msg, true, :query, [], _answers, [], _resources, state) do
    state
  end


  defp handle_record(_srcaddr, _type, _qr, _opcode, _questions, _answers, _authorities, _resources, state) do
    state
  end

  defp questions(record) do
    #  {:dns_query, '_companion-link._tcp.local', :ptr, :in},
    record
    |> :inet_dns.msg(:qdlist)
    |> Enum.map(&:inet_dns.dns_query/1)
    |> Enum.map(&Enum.into(&1, %{}))
  end

  defp answers(record) do
    rr(record, :anlist)
  end

  defp authorities(record) do
    rr(record, :nslist)
  end

  defp resources(record) do
    rr(record, :arlist)
  end

  defp rr(resources, type) do
    resources
    |> :inet_dns.msg(type)
    |> Enum.map(&:inet_dns.rr/1)
    |> Enum.map(&Enum.into(&1, %{}))
  end
end
