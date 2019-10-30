defmodule Madam.Client.Resolver do
  alias Madam.Service

  use GenServer, restart: :transient

  @oneshot_timeout 3_000

  def start_link({opts, from}) do
    GenServer.start_link(__MODULE__, {opts, from})
  end

  def init({opts, from}) do
    service = Keyword.fetch!(opts, :service)
    protocol = Keyword.get(opts, :protocol, :tcp)
    domain = Keyword.get(opts, :domain, "local")
    timeout = Keyword.get(opts, :timeout, @oneshot_timeout)

    service_opts = [service: service, protocol: protocol, domain: domain]
    service = Service.service_domain(service_opts)

    state = %{service: service, service_opts: service_opts, from: from, results: [], socket: nil}

    {:ok, state, {:continue, {:resolve, timeout}}}
  end

  def handle_continue({:resolve, timeout}, state) when is_integer(timeout) do
    %{from: from} = state

    msg =
      :inet_dns.make_msg(
        header: header(),
        qdlist: queries(state)
      )
    packet = :inet_dns.encode(msg)

    {:ok, socket} = Madam.UDP.open(:resolve)

    :ok = Madam.UDP.send(socket, packet)

    _ref = Process.send_after(self(), :timeout, timeout)

    {:noreply, %{state | socket: socket}}
  end

  def handle_info(:timeout, state) do
    %{from: from, results: results, socket: socket} = state
    Madam.UDP.close(socket)
    GenServer.reply(from, {:ok, results})
    {:stop, :normal, state}
  end

  def handle_info({:udp, _socket, addr, port, data}, state) do
    {:ok, record} = :inet_dns.decode(data)
    header = :inet_dns.header(:inet_dns.msg(record, :header))

    state =
      handle_record(
        :inet_dns.record_type(record),
        header[:qr],
        header[:opcode],
        questions(record),
        answers(record),
        resources(record),
        state
      )

    {:noreply, state}
  end

  defp questions(record) do
    record
    |> :inet_dns.msg(:qdlist)
    |> Enum.map(&:inet_dns.dns_query/1)
    |> Enum.map(&Enum.into(&1, %{}))
    |> Enum.map(&stringify_record/1)
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
    |> Enum.map(&Enum.into(&1, %{}))
  end

  defp handle_record(:msg, true, :query, [], answers, resources, state) do
    %{service_opts: service_opts, results: results} = state

    answers =
      answers
      |> Enum.filter(fn answer ->
        answer.type == :ptr && answer.domain == state.service
      end)

    case answers do
      [] ->
        state

      [answer | _] ->
        instance = answer.data

        with {:ok, srv} <- find_srv(resources, instance),
             [_ | _] = a <- find_a(resources, srv),
             [_ | _] = txt <- find_txt(resources, instance),
             %{data: {priority, weight, port, host}} <- srv do

          data =
            txt
            |> Enum.flat_map(&Map.fetch!(&1, :data))
            |> Enum.reject(&(byte_size(&1) == 0))

          [hostname | _rest] = Service.split_name(host)
          [name | _rest] = Service.split_name(instance)

          params =
            Keyword.merge(service_opts,
              name: name,
              hostname: hostname,
              port: port,
              priority: priority,
              data: data,
              weight: weight,
              addrs: Enum.map(a, &Map.fetch!(&1, :data))
            )

          service = struct(Service, params)
          %{state | results: [service | results]}
        else
          _ ->
            state
        end
    end
  end

  defp find_srv(resources, instance) do
    srv =
      Enum.find(resources, fn
        %{type: :srv, domain: ^instance} -> true
        _ -> false
      end)

    case srv do
      %{data: {priority, weight, port, host}} ->
        {:ok, %{srv | data: {priority, weight, port, to_string(host)}}}

      srv ->
        :error
    end
  end

  defp find_a(resources, %{type: :srv, data: {_priority, _weight, _port, host}}) do
    Enum.reduce(resources, [], fn
      %{type: :a, domain: ^host} = resource, acc ->
        [resource | acc]

      _, acc ->
        acc
    end)
  end

  defp find_txt(resources, instance) do
    Enum.reduce(resources, [], fn
      %{type: :txt, domain: ^instance} = resource, acc ->
        [resource | acc]

      _, acc ->
        acc
    end)
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

  defp handle_record(type, qr, opcode, questions, answers, resources, state) do
    # IO.inspect [type, qr, opcode, questions, answers]
    state
  end

  defp header do
    :inet_dns.make_header(
      id: 0,
      qr: false,
      opcode: :query,
      aa: false,
      tc: false,
      rd: false,
      ra: false,
      pr: false,
      rcode: 0
    )
  end

  def queries(state) do
    %{service: service} = state

    query =
      :inet_dns.make_dns_query(
        # set top bit of class to signify that we prefer unicast responses
        # class: 0b1000000000000001, # :in,
        class: :in,
        type: :ptr,
        domain: to_charlist(service)
      )

    [query]
  end
end
