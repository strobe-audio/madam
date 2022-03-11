defmodule Madam.Announcer do
  use GenServer

  alias Madam.{Service, DNS}

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    {:ok, service_opts} = Keyword.fetch(args, :service)

    {_module, _opts} = udp = Keyword.get(args, :udp, {Madam.UDP, []})

    service = Madam.Service.new(service_opts)
    domain = Madam.Service.service_domain(service) |> IO.inspect()

    Registry.register(Madam.Service.Registry, {:srv, domain}, [])
    Registry.register(Madam.Service.Registry, {:a, service.hostname}, [])

    {:ok, %{service: service, udp: udp}, random_timeout(:initial)}
  end

  @impl true
  def handle_continue(:announce, state) do
    IO.inspect(announce: state.service, udp: state.udp)
    :ok = announce(nil, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({Madam, :query, %DNS.Msg{} = msg}, state) do
    :ok = announce(msg, state)

    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    Logger.info(fn ->
      [
        "Announcing service ",
        Service.service_domain(state.service),
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
        ifname: address.ifname,
        ifaddr: address.ifaddrs,
        addr: {}
      }
    end)
    |> Enum.each(&announce(&1, state))
  end

  defp announce(msg, state) do
    response = %{
      msg
      | qr: true,
        aa: true,
        opcode: :query,
        questions: [],
        answers: answers(state.service),
        resources: resources(msg, state.service)
    }

    {module, args} = state.udp

    apply(module, :broadcast, [response | args])
  end

  defp answers(service) do
    ptrs(service)
  end

  defp ptrs(service) do
    ptr = %DNS.RR{
      type: :ptr,
      domain: Service.service_domain(service, false) |> to_charlist(),
      class: :in,
      ttl: service.ttl,
      data: to_charlist(Service.instance_name(service, false))
    }

    Logger.debug([
      Service.service_domain(service, false),
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

  defp anchors(%DNS.Msg{ifaddr: []} = msg, service) do
    ips = Madam.private_ips()
    anchors(%{msg | ifaddr: ips}, service)
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
