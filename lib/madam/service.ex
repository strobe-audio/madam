defmodule Madam.Service do
  @enforce_keys [:name, :port, :service]

  use GenServer

  require Logger

  alias __MODULE__

  defstruct [
    :name,
    :port,
    :service,
    :hostname,
    data: [],
    protocol: :tcp,
    domain: "local",
    ttl: 120,
    weight: 10,
    priority: 10,
    addrs: []
  ]

  def instance_name(service, fq \\ false) do
    "#{escape_name(service.name)}.#{service_domain(service, fq)}"
  end

  def service_domain(service, fq \\ false)

  def service_domain(%Service{} = service, fq) do
    "_#{service.service}._#{service.protocol}.#{service.domain}#{if fq, do: ".", else: ""}"
  end

  def service_domain(service, fq) when is_list(service) do
    "_#{service[:service]}._#{service[:protocol]}.#{service[:domain]}#{if fq, do: ".", else: ""}"
  end

  def hostname(%Service{} = service, fq \\ false) do
    "#{service.hostname}.#{service.domain}#{if fq, do: ".", else: ""}"
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

  def start_link(%Service{} = service) do
    GenServer.start_link(__MODULE__, service)
  end

  def start_link(opts) when is_list(opts) do
    service = struct(__MODULE__, opts)
    start_link(service)
  end

  def generate_hostname(service) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{service.service}-#{service.port}-#{random}"
  end

  @impl true
  def init(service) do
    domain = service_domain(service)
    service = Map.put(service, :hostname, generate_hostname(service))
    Registry.register(Madam.Service.Registry, {:ptr, domain}, [])
    Registry.register(Madam.Service.Registry, {:a, hostname(service)}, [])
    {:ok, service, random_timeout(:initial)}
  end

  @impl true
  def handle_info({:announce, :a, {_ip, _port} = addr, answers}, service) do
    cached = Enum.map(answers, fn %{domain: instance, ttl: ttl} -> {to_string(instance), ttl} end)

    me = hostname(service, false)

    is_cached? =
      Enum.any?(cached, fn {instance, ttl} ->
        instance == me && ttl > service.ttl / 2
      end)

      if is_cached? do
        Logger.debug(fn -> "Cached" end)
      else
        msg =
          :inet_dns.make_msg(
            header: header(),
            anlist: anchors(service),
            arlist: []
          )

        :ok = Madam.Advertise.dns_send(addr, [msg])
      end

    {:noreply, service}
  end

  @impl true
  def handle_info({:announce, :ptr, {_ip, _port} = addr, answers}, service) do
    cached = Enum.map(answers, fn %{data: instance, ttl: ttl} -> {to_string(instance), ttl} end)

    me = instance_name(service, false)

    # spec says to only re-send the zone if the version in the answers is at 50%
    # of our ttl
    is_cached? =
      Enum.any?(cached, fn {instance, ttl} ->
        instance == me && ttl > service.ttl / 2
      end)

      unless is_cached? do
        announce(addr, service)
      end

    {:noreply, service}
  end

  def handle_info(:timeout, service) do
    {:noreply, announce({}, service)}
  end

  def handle_info(_msg, service) do
    {:noreply, service}
  end

  defp announce(addr, service) do
    packets = packet(addr, service)
    :ok = Madam.Advertise.dns_send(addr, packets)
    service
  end

  defp packet(addr, service) do
    msg =
      :inet_dns.make_msg(
        header: header(),
        anlist: answers(service),
        arlist: resources(addr, service)
      )

    [msg]
  end

  defp header do
    :inet_dns.make_header(
      id: 0,
      qr: true,
      opcode: :query,
      aa: true,
      tc: false,
      rd: false,
      ra: false,
      pr: false,
      rcode: 0
    )
  end

  defp answers(service) do
    ptr =
      :inet_dns.make_rr(
        type: :ptr,
        domain: service_domain(service, true) |> to_charlist(),
        class: :in,
        ttl: service.ttl,
        data: to_charlist(instance_name(service, true))
      )

    Logger.debug([
      service_domain(service, true),
      " #{service.ttl} ",
      " IN ",
      " PTR ",
      instance_name(service, true)
    ])

    [ptr]
  end

  defp resources(addr, service) do
    services(service) ++ anchors(addr, service) ++ texts(service)
  end

  defp services(service) do
    target = to_charlist(hostname(service, true))

    srv =
      :inet_dns.make_rr(
        type: :srv,
        domain: instance_name(service, true) |> to_charlist(),
        class: :in,
        ttl: service.ttl,
        data: {service.priority, service.weight, service.port, target}
      )

    Logger.debug([
      instance_name(service, true),
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

  defp anchors(service) do
    ips = Madam.private_ips()
    anchors_for_ips(ips, service)
  end

  defp anchors({}, service) do
    ips = Madam.private_ips()
    anchors_for_ips(ips, service)
  end

  defp anchors({ip, _port}, service) do
    ips = Madam.response_ips(ip)
    anchors_for_ips(ips, service)
  end

  defp anchors_for_ips(ips, service) do
    target = to_charlist(hostname(service, true))

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
        :inet_dns.make_rr(
          type: type,
          domain: target,
          class: :in,
          ttl: service.ttl,
          data: ip
        )
      ]
    end)
  end

  defp texts(service) do
    data = Enum.map(service.data, fn {k, v} -> to_charlist("#{k}=#{v}") end)

    txt =
      :inet_dns.make_rr(
        domain: instance_name(service) |> to_charlist(),
        type: :txt,
        class: :in,
        ttl: service.ttl,
        data: data
      )

    [txt]
  end

  def random_timeout(:initial) do
    :crypto.rand_uniform(500, 1500)
  end

  def random_timeout(:announcements, _ttl) do
    # :crypto.rand_uniform(ttl * 100, ttl * 500)
    5_000
  end
end
