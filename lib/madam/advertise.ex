defmodule Madam.Advertise do
  use GenServer

  @port 5353
  @address4 {224, 0, 0, 251}
  @address6 {3842, 0, 0, 0, 0, 0, 0, 251}
  @bind4 {0, 0, 0, 0}
  @bind6 {0, 0, 0, 0, 0, 0, 0, 0}

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def dns_send(addr, packets) when is_list(packets) do
    GenServer.call(__MODULE__, {:dns_send, addr, packets})
  end

  def init(config) do

    udp4_options = [
      {:mode, :binary},
      {:reuseaddr, true},
      {:ip, @address4},
      {:multicast_ttl, 4},
      {:multicast_loop, true},
      {:broadcast, true},
      {:add_membership, {@address4, @bind4}},
      {:active, true}
    ]

    {:ok, socket4} = :gen_udp.open(@port, udp4_options)

    # {:ok, send_socket} = :gen_udp.open(0, [:binary])

    {:ok, %{socket: socket4}}
  end

  defp send_packet(state, address, @port, packet) when tuple_size(address) == 4 do
    :gen_udp.send(state.socket, @address4, @port, packet)
  end

  defp send_packet(state, address, port, packet) when tuple_size(address) == 4 do
    :gen_udp.send(state.socket, address, port, packet)
  end

  defp send_packet(state, address, @port, packet) when tuple_size(address) == 8 do
    :gen_udp.send(state.socket6, @address6, @port, packet)
  end

  defp send_packet(state, address, port, packet) when tuple_size(address) == 8 do
    :gen_udp.send(state.socket6, address, port, packet)
  end

  def handle_call({:dns_send, {ip, port}, packets}, _from, state) do
    %{socket: _socket} = state
    {:ok, socket} = :gen_udp.open(0, [:binary])

    packets
    |> Stream.map(&:inet_dns.encode/1)
    |> Enum.each(fn packet ->
      # IO.inspect addr: {ip, port}, encoded_packet: packet
      # :ok = :gen_udp.send(socket, @address, @port, packet)
      send_packet(state, ip, port, packet)
    end)
    {:reply, :ok, state}
  end

  def handle_info({:udp, socket, addr, port, data}, state) do
    {:ok, record} = :inet_dns.decode(data) #|> IO.inspect
    header = :inet_dns.header(:inet_dns.msg(record, :header))
    IO.inspect [
      addr: {addr, port},
      type: :inet_dns.record_type(record),
      qr: header[:qr],
      opcode: header[:opcode],
      questions: questions(record),
      answers: answers(record),
      authorities: authorities(record),
      resources: resources(record),
    ]
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

  # def handle_info(msg, state) do
  #   {:noreply, state}
  # end

  # defp handle_record(src_addr, type, qr, opcode, questions, answers, authorities, resources, state)

  defp handle_record(src_addr, :msg, false, :query, [%{domain: domain, type: :ptr}], answers, [], [], state) do
    domain = to_string(domain)
    # announce
    IO.inspect ptr: domain
    Registry.dispatch(Madam.Service.Registry, domain, fn entries ->
      # IO.inspect [dispatch: entries]
      # IO.inspect [ptr: domain, addr: src_addr, answers: answers]
      for {pid, _opts} <- entries, do: send(pid, {:announce, src_addr, answers})
    end)
    state
  end

  defp handle_record(src_addr, :msg, true, :query, [], answers, [], resources, state) do
    # notify service
    # IO.inspect [service: src_addr, answers: answers]
    state
  end


  defp handle_record(srcaddr, type, qr, opcode, questions, answers, authorities, resources, state) do
    # IO.inspect srcaddr: srcaddr, type: type,qr: qr,opcode: opcode,questions: questions,answers: answers,authorities: authorities,resources: resources
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
