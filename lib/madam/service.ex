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
    priority: 10
  ]

  def instance_name(service, fq \\ false) do
    "#{service.name}.#{service_domain(service, fq)}"
  end

  def hostname(%Service{} = service, fq \\ false) do
    "#{service.name}.#{service_domain(service, fq)}"
  end

  def service_domain(%Service{} = service, fq \\ false) do
    "_#{service.service}._#{service.protocol}.#{service.domain}#{if fq, do: ".", else: ""}"
  end

  def advertise(config) do
    service = struct(__MODULE__, config)
    Service.Supervisor.advertise(service)
  end

  def start_link(%Service{} = service) do
    # IO.inspect(start_link: service)
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
    Registry.register(Madam.Service.Registry, domain, [])
    {:ok, {{}, service}}
  end

  @impl true
  def handle_info({:announce, {_ip, _port} = addr, _answers}, {_, service} = state) do
    {:noreply, announce(addr, state)}
  end

  # def handle_info(:timeout, {_, service} = state) do
  #   {:noreply, announce(state)}
  # end

  def handle_info(msg, state) do
    # IO.inspect(here: msg)
    {:noreply, state}
  end

  defp announce(addr, {_, service} = state) do
    IO.inspect(announce: service)
    packets = packet(addr, service)
    IO.inspect(send: addr)
    :ok = Madam.Advertise.dns_send(addr, packets)
    state
  end

  defp packet(addr, service) do
    {:ok, hostname} = :inet.gethostname()

    msg =
      :inet_dns.make_msg(
        header: header(),
        anlist: answers(addr, service),
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

  defp answers(addr, service) do
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

    records = [ptr]
  end

  defp resources(addr, service) do
    services(addr, service) ++ texts(addr, service)
  end

  defp services({ip, _port}, service) do
    # {:ok, hostname} = :inet.gethostname()
    hostname = "what-is-this-34889"
    target = to_charlist("#{service.hostname}.")

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

    host_ips = Madam.private_ips()

    a =
      host_ips
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

    [srv] ++ a
  end

  defp texts(addr, service) do
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
    # :crypto.rand_uniform(500, 1500)
    1_000
  end

  def random_timeout(:announcements, ttl) do
    # :crypto.rand_uniform(ttl * 100, ttl * 500) |> IO.inspect
    5_000
  end
end
