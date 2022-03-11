defmodule Madam.Network do
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
    flags = Keyword.get(opts, :flags)

    addrs =
      opts
      |> Keyword.get_values(:addr)
      |> Enum.reject(&is_ipv6_addr/1)

    :loopback in flags || length(addrs) == 0
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
end
