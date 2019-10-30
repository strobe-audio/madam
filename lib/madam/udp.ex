defmodule Madam.UDP do
  @address {224, 0, 0, 251}
  @address4 {224, 0, 0, 251}
  @port 5353
  @bind4 {0, 0, 0, 0}

  # [{multicast_if, InterfaceIP},
  #  {reuseaddr, true},
  #  {multicast_ttl,4},
  #  %    {multicast_loop,false},
  #  %    {broadcast, true},
  #  {active, true},
  #  {mode, binary},
  #  {ip, MulticastIP},
  #  {add_membership,{MulticastIP, InterfaceIP}}]
  def open(:announce) do
    opts = [
      # multicast_if: {0, 0, 0, 0},
      # reuseaddr: true,
      # multicast_ttl: 4,
      mode: :binary,
      # ip: @address,
      # add_membership: {@address, {0, 0, 0, 0}}
    ]
    with {:ok, socket} <- open(0, opts) do
      {:ok, socket, @address, @port}
    end
  end

  def open(:resolve) do
    udp4_options = [
      :inet,
      {:mode, :binary},
      {:reuseaddr, true},
      {:ip, @address4},
      {:multicast_if, @address4},
      {:multicast_ttl, 4},
      {:multicast_loop, true},
      {:broadcast, true},
      {:add_membership, {@address4, @bind4}},
      {:active, true}
    ]
    open(@port, udp4_options)
  end

  defp open(port, opts) do
    :gen_udp.open(port, opts)
  end

  def send(socket, msg) do
    :gen_udp.send(socket, @address4, @port, msg)
  end

  def close(socket) do
    :gen_udp.close(socket)
  end
end