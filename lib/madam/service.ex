defmodule Madam.Service do
  @enforce_keys [:name, :port, :service]

  use GenServer

  require Logger

  alias __MODULE__
  alias Madam.DNS

  defstruct [
    :name,
    :port,
    :service,
    :hostname,
    data: %{},
    protocol: :tcp,
    ttl: 120,
    weight: 10,
    priority: 10,
    addrs: []
  ]

  def new(%__MODULE__{} = service) do
    put_hostname(service)
  end

  def new(params) when is_list(params) do
    __MODULE__
    |> struct(params)
    |> put_hostname()
  end

  defp put_hostname(%{hostname: empty} = service) when empty in [nil, ""] do
    %{service | hostname: generate_hostname(service)}
  end

  def from_dns(%Madam.DNS.Msg{answers: answers, resources: resources}) do
    records = Enum.concat(answers, resources)

    Enum.reduce(
      records,
      %__MODULE__{data: %{}, name: "", port: 0, service: ""},
      &build_from_dns/2
    )
  end

  defp build_from_dns(%{type: :txt, data: data}, service) do
    %{service | data: Map.merge(service.data, Madam.DNS.decode_txt(data))}
  end

  defp build_from_dns(%{type: :srv, data: {priority, weight, port, host}}, service) do
    %{service | priority: priority, weight: weight, port: port, hostname: to_string(host)}
  end

  defp build_from_dns(%{type: :ptr, data: data, domain: <<"_", domain::binary>> = d} = r, service) do
    name =
      case split_name(data) do
        [name | _] ->
          name

        _other ->
          ""
      end

    service =
      case String.split(domain, ".") do
        [s, "_tcp", "local"] ->
          %{service | ttl: r.ttl, service: s, protocol: :tcp}

        [s, "_udp", "local"] ->
          %{service | ttl: r.ttl, service: s, protocol: :udp}

        _other ->
          Logger.warn(fn -> ["weird srv record: ", d] end)
          %{service | ttl: r.ttl, service: d}
      end

    %{service | name: name}
  end

  defp build_from_dns(%{type: :a, data: ip}, %{addrs: addrs} = service) do
    %{service | addrs: [ip | addrs]}
  end

  defp build_from_dns(%{type: :aaaa, data: _ip}, %{addrs: _addrs} = service) do
    # %{service | addrs: [ip | addrs]}
    service
  end

  defp build_from_dns(_rr, service) do
    service
  end

  def instance_name(service, fq \\ false) do
    "#{escape_name(service.name)}.#{domain(service, fq)}"
  end

  def domain(service, fq \\ false)

  def domain(%Service{} = service, fq) do
    "_#{service.service}._#{service.protocol}.local#{if fq, do: ".", else: ""}"
  end

  def domain(service, fq) when is_list(service) do
    "_#{service[:service]}._#{service[:protocol]}.local#{if fq, do: ".", else: ""}"
  end

  def domain(service, protocol, _domain) do
    "_#{service}._#{protocol}.local"
  end

  def hostname(%Service{} = service, fq \\ false) do
    "#{service.hostname}.local#{if fq, do: ".", else: ""}"
  end

  def advertise(config) do
    service = struct(__MODULE__, config)
    Service.Supervisor.advertise(service)
  end

  def split_name(name) do
    split_name(name, <<>>, [])
  end

  defp split_name(<<>>, part, acc) do
    Enum.reverse([part | acc])
  end

  defp split_name(<<"\\", ".", rest::binary>>, part, acc) do
    split_name(rest, part <> ".", acc)
  end

  defp split_name(<<".", rest::binary>>, part, acc) do
    split_name(rest, "", [part | acc])
  end

  defp split_name(<<c::binary-1, rest::binary>>, part, acc) do
    split_name(rest, part <> c, acc)
  end

  defp escape_name(name) do
    String.replace(name, ".", "\\.")
  end

  def generate_hostname(service) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{service.service}-#{service.port}-#{random}"
  end

  def child_spec(args) do
    case Keyword.fetch(args, :service) do
      {:ok, service_spec} ->
        %{
          id: child_spec_id(service_spec),
          start: {__MODULE__, :start_link, [args]}
        }

      :error ->
        raise ArgumentError,
          message: "#{__MODULE__} arguments missing required :service definition"
    end
  end

  defp child_spec_id(%Madam.Service{} = service) do
    {__MODULE__, service.service}
  end

  defp child_spec_id(service) when is_list(service) do
    {__MODULE__, service[:service]}
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {:ok, service_opts} = Keyword.fetch(args, :service)

    {_module, _opts} = udp = Keyword.get(args, :udp, {Madam.UDP, []})

    service = Madam.Service.new(service_opts)
    domain = Madam.Service.domain(service)

    Registry.register(Madam.Service.Registry, {:srv, domain}, [])
    Registry.register(Madam.Service.Registry, {:a, service.hostname}, [])
    Registry.register(Madam.Service.Registry, {:a, Service.instance_name(service, false)}, [])

    {:ok, %{service: service, udp: udp}, random_timeout(:initial)}
  end

  @impl true
  def handle_continue(:announce, state) do
    :ok = announce(nil, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({Madam, {:query, :ptr}, %DNS.Msg{} = msg}, state) do
    :ok = announce(msg, state)

    {:noreply, state}
  end

  def handle_info({Madam, {:query, :a}, %DNS.Msg{} = msg}, state) do
    # TODO: if the msg with the query for the service contains a list
    # of answers, and one of those answers has a domain set to the current
    # hostname, then the if the answer's ttl is > (the service ttl / 2)
    # the response is cached and we don't need to send one
    response = %{
      msg
      | qr: true,
        aa: true,
        opcode: :query,
        questions: [],
        answers: anchors(msg, state.service),
        resources: []
    }

    send_msg(response, state)

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    Logger.info(fn ->
      [
        "Announcing service ",
        Service.domain(state.service),
        ":",
        to_string(state.service.port)
      ]
    end)

    :ok = announce(nil, state)
    {:noreply, state}
  end

  defp announce(nil, state) do
    # construct a set of fake source messages, one for each interface/ip address we're listening
    # on so that we can send out a bunch of DNS messages with each A entry matching the interface
    # it's being sent out on
    Madam.UDP.list()
    |> Enum.map(fn {_pid, address} ->
      %DNS.Msg{
        qr: false,
        ifname: address.ifname,
        ifaddr: address.ifaddrs,
        addr: {}
      }
    end)
    |> Enum.each(&announce(&1, state))
  end

  defp announce(msg, state) do
    # TODO: if the msg with the query for the service contains a list
    # of answers, and one of those answers has a domain set to the current
    # hostname, then the if the answer's ttl is > (the service ttl / 2)
    # the response is cached and we don't need to send one
    response = %{
      msg
      | qr: true,
        aa: true,
        opcode: :query,
        questions: [],
        answers: answers(state.service),
        resources: resources(msg, state.service)
    }

    send_msg(response, state)
  end

  defp send_msg(msg, state) do
    {module, args} = state.udp

    apply(module, :broadcast, [msg | args])
  end

  defp answers(service) do
    ptrs(service)
  end

  defp ptrs(service) do
    ptr = %DNS.RR{
      type: :ptr,
      domain: Service.domain(service, false) |> to_charlist(),
      class: :in,
      ttl: service.ttl,
      data: to_charlist(Service.instance_name(service, false))
    }

    Logger.debug([
      Service.domain(service, false),
      " #{service.ttl} ",
      " IN ",
      " PTR ",
      Service.instance_name(service, false)
    ])

    [ptr]
  end

  defp resources(msg, service) do
    services(service) ++ anchors(msg, service) ++ texts(service)
  end

  defp services(service) do
    target = to_charlist(Service.hostname(service, false))

    srv = %DNS.RR{
      type: :srv,
      domain: Service.instance_name(service, false) |> to_charlist(),
      class: :in,
      ttl: service.ttl,
      data: {service.priority, service.weight, service.port, target}
    }

    Logger.debug([
      Service.instance_name(service, false),
      " #{service.ttl} ",
      " IN ",
      " SRV ",
      to_string(service.priority),
      " #{service.weight} ",
      " #{service.port} ",
      target
    ])

    [srv]
  end

  defp anchors(msg, service) do
    anchors_for_ips(msg.ifaddr, service)
  end

  defp anchors_for_ips(ips, service) when is_list(ips) do
    target = to_charlist(Service.hostname(service, false))

    ips
    |> Enum.flat_map(fn ip ->
      type =
        case tuple_size(ip) do
          4 -> :a
          8 -> :aaaa
        end

      Logger.debug([
        target,
        " #{service.ttl} ",
        " IN ",
        " #{to_string(type) |> String.upcase()} ",
        ip |> Tuple.to_list() |> Enum.join(".")
      ])

      [
        %DNS.RR{type: type, domain: target, class: :in, ttl: service.ttl, data: ip}
      ]
    end)
  end

  defp texts(service) do
    data = DNS.encode_txt(service.data)

    txt = %DNS.RR{
      domain: Service.instance_name(service, false) |> to_charlist(),
      type: :txt,
      class: :in,
      ttl: service.ttl,
      data: data
    }

    [txt]
  end

  def random_timeout(:initial) do
    :rand.uniform(1500) + 499
  end
end
