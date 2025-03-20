defmodule Madam.Network.Utils do
  import Bitwise

  def ip_to_i({a, b, c, d}) do
    (a <<< 24) + (b <<< 16) + (c <<< 8) + d
  end

  def ip_to_i({a, b, c, d, e, f, g, h}) do
    (a <<< 56) + (b <<< 48) + (c <<< 40) + (d <<< 32) + (e <<< 24) + (f <<< 16) + (g <<< 8) + h
  end
end

defmodule Madam.Network do
  import Bitwise

  import Madam.Network.Utils

  def interfaces do
    with {:ok, ifaddrs} <- :inet.getifaddrs() do
      interfaces(ifaddrs)
    end
  end

  def interfaces(ifaddrs) do
    interfaces =
      ifaddrs
      |> Stream.reject(&reject_loopback_down/1)
      |> Enum.map(&if_ips/1)

    {:ok, interfaces}
  end

  defp reject_loopback_down({_, opts}) do
    _flags = Keyword.get(opts, :flags)

    addrs =
      opts
      |> Keyword.get_values(:addr)
      |> Enum.reject(&is_ipv6_addr/1)

    # :loopback in flags || length(addrs) == 0
    length(addrs) == 0
  end

  defp is_ipv6_addr({_, _, _, _}), do: false
  defp is_ipv6_addr({_, _, _, _, _, _, _, _}), do: true

  defp if_ips({i, opts}) do
    addrs =
      opts
      |> Keyword.get_values(:addr)
      |> Enum.reject(&is_ipv6_addr/1)

    {to_string(i), addrs}
  end

  def response_ips(src_ip) do
    {:ok, ifaddrs} = :inet.getifaddrs()

    ips = Enum.flat_map(ifaddrs, &find_if(&1, src_ip, tuple_size(src_ip)))

    ips
  end

  defp find_if({_name, opts}, src_ip, 4) do
    ips =
      opts
      |> Keyword.get_values(:addr)
      |> Enum.filter(fn addr -> tuple_size(addr) == 4 end)

    netmasks =
      opts
      |> Keyword.get_values(:netmask)
      |> Enum.filter(fn addr -> tuple_size(addr) == 4 end)

    case netmasks do
      [netmask] ->
        mask = ip_to_i(netmask)
        src = ip_to_i(src_ip) &&& mask
        Enum.filter(ips, fn ip -> (ip_to_i(ip) &&& mask) == src end)

      [] ->
        []
    end
  end

  @private_v4_ranges [
    # 10.0.0.0/8
    {{10, 0, 0, 0}, {255, 0, 0, 0}},
    # 192.168.0.0/16
    {{192, 168, 0, 0}, {255, 255, 0, 0}},
    # 172.16.0.0/12
    {{172, 16, 0, 0}, {255, 240, 0, 0}}
  ]

  # @private_v6_ranges [
  #   # fd00::/8
  #   {{64768, 0, 0, 0, 0, 0, 0, 0}, {65280, 0, 0, 0, 0, 0, 0, 0}},
  #   # fe80::/10
  #   {{65152, 0, 0, 0, 0, 0, 0, 0}, {65535, 49152, 0, 0, 0, 0, 0, 0}}
  # ]

  @private_v4 Enum.map(@private_v4_ranges, fn {ip, netmask} ->
                {ip_to_i(ip) &&& ip_to_i(netmask), ip_to_i(netmask)}
              end)

  # @private_v6 Enum.map(@private_v6_ranges, fn {ip, netmask} ->
  #               {ip_to_i(ip) &&& ip_to_i(netmask), ip_to_i(netmask)}
  #             end)

  def private_network?(ipv6, netmask) when tuple_size(ipv6) == 8 and tuple_size(netmask) == 8 do
    false
    # private_network?(ipv6, netmask, @private_v6)
  end

  def private_network?(ipv4, netmask) when tuple_size(ipv4) == 4 and tuple_size(netmask) == 4 do
    private_network?(ipv4, netmask, @private_v4)
  end

  def private_network?({ipv6, netmask}) when tuple_size(ipv6) == 8 and tuple_size(netmask) == 8 do
    false
    # private_network?(ipv6, netmask, @private_v6)
  end

  def private_network?({ipv4, netmask}) when tuple_size(ipv4) == 4 and tuple_size(netmask) == 4 do
    private_network?(ipv4, netmask, @private_v4)
  end

  defp private_network?(addr, _netmask, private) do
    ip = ip_to_i(addr)

    Enum.any?(private, fn {masked, mask} ->
      (ip &&& mask) == masked
    end)
  end

  def private_networks do
    {:ok, ifs} = :inet.getifaddrs()

    ifs
    |> Enum.flat_map(fn {_name, opts} ->
      addrs = Keyword.get_values(opts, :addr)
      masks = Keyword.get_values(opts, :netmask)
      Enum.zip(addrs, masks)
    end)
    |> Enum.filter(&private_network?/1)
  end

  def private_ips do
    private_networks()
    |> Enum.map(fn {ip, _netmask} -> ip end)
  end
end
