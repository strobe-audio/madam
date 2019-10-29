defmodule Madam.UDP do
  @address {224, 0, 0, 251}
  @port 5353

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

  defp open(port, opts) do
    :gen_udp.open(port, opts)
  end
end