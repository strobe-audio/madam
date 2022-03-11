defmodule Madam.NetworkTest do
  use ExUnit.Case, async: true

  describe "interfaces/1" do
    @ifaddrs [
      {'lo',
       [
         flags: [:up, :loopback, :running],
         addr: {127, 0, 0, 1},
         netmask: {255, 0, 0, 0},
         addr: {0, 0, 0, 0, 0, 0, 0, 1},
         netmask: {65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535},
         hwaddr: [0, 0, 0, 0, 0, 0]
       ]},
      {'eth0',
       [
         flags: [:up, :broadcast, :running, :multicast],
         hwaddr: [232, 106, 100, 61, 237, 71]
       ]},
      {'wlan0',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {192, 168, 1, 235},
         netmask: {255, 255, 255, 0},
         broadaddr: {192, 168, 1, 255},
         addr: {64768, 0, 0, 1, 48967, 56943, 1797, 10730},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         addr: {10752, 9159, 50304, 23809, 19896, 35257, 30302, 16515},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         addr: {65152, 0, 0, 0, 46419, 43176, 40311, 55867},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         hwaddr: [24, 29, 234, 253, 75, 72]
       ]},
      {'tailscale0',
       [
         flags: [:up, :pointtopoint, :running, :multicast],
         addr: {100, 111, 184, 97},
         netmask: {255, 255, 255, 255},
         dstaddr: {100, 111, 184, 97},
         addr: {64890, 4444, 41440, 43794, 18499, 52630, 25199, 47201},
         netmask: {65535, 65535, 65535, 65535, 65535, 65535, 65535, 65535},
         addr: {65152, 0, 0, 0, 6404, 44371, 51003, 42604},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0}
       ]},
      {'ztmjfbvxxm',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {10, 251, 251, 40},
         netmask: {255, 255, 255, 0},
         broadaddr: {10, 251, 251, 255},
         addr: {64896, 22210, 57884, 55356, 61593, 37687, 16075, 32523},
         netmask: {65535, 65535, 65535, 65535, 65535, 65280, 0, 0},
         addr: {65152, 0, 0, 0, 61451, 59135, 65239, 40393},
         netmask: {65535, 65535, 65535, 65535, 0, 0, 0, 0},
         hwaddr: [242, 11, 230, 215, 157, 201]
       ]},
      {'br-3025497ba651',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {172, 18, 0, 1},
         netmask: {255, 255, 0, 0},
         broadaddr: {172, 18, 255, 255},
         hwaddr: [2, 66, 135, 110, 170, 108]
       ]},
      {'docker0',
       [
         flags: [:up, :broadcast, :running, :multicast],
         addr: {172, 17, 0, 1},
         netmask: {255, 255, 0, 0},
         broadaddr: {172, 17, 255, 255},
         hwaddr: [2, 66, 194, 81, 187, 232]
       ]}
    ]

    test "returns all interfaces with ipv4 addresses" do
      {:ok, ifs} = Madam.Network.interfaces(@ifaddrs)

      assert ifs == [
               {"wlan0", [{192, 168, 1, 235}]},
               {"tailscale0", [{100, 111, 184, 97}]},
               {"ztmjfbvxxm", [{10, 251, 251, 40}]},
               {"br-3025497ba651", [{172, 18, 0, 1}]},
               {"docker0", [{172, 17, 0, 1}]}
             ]
    end
  end
end
