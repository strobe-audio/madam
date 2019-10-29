defmodule MadamTest do
  use ExUnit.Case

  describe "private_network?/2" do
    private_ipsv4 = [
      # {ip, netmask}
      Macro.escape({{10, 251, 251, 40}, {10, 251, 251, 40}}),
      Macro.escape({{10, 0, 0, 1}, {10, 12, 0, 0}}),
      Macro.escape({{192, 168, 1, 62}, {255, 255, 255, 0}}),
      Macro.escape({{172, 16, 0, 1}, {255, 255, 255, 0}}),
      Macro.escape({{172, 17, 3, 12}, {255, 255, 0, 0}}),
      Macro.escape({{172, 31, 254, 254}, {255, 240, 0, 0}})
    ]

    public_ipsv4 = [
      Macro.escape({{127, 0, 0, 1}, {255, 0, 0, 0}}),
      Macro.escape({{123, 51, 12, 18}, {255, 255, 255, 0}}),
      Macro.escape({{172, 32, 3, 12}, {255, 240, 0, 0}})
    ]

    private_ipsv6 = [
      Macro.escape(
        {{65152, 0, 0, 0, 8456, 42002, 59216, 40057}, {65535, 65535, 65535, 65535, 0, 0, 0, 0}}
      ),
      Macro.escape(
        {{64896, 22210, 57884, 55356, 61593, 37632, 13572, 23113},
         {65535, 65535, 65535, 65535, 65535, 65280, 0, 0}}
      )
    ]

    for {ip, netmask} <- private_ipsv4 do
      test "#{Macro.to_string(ip)}/#{Macro.to_string(netmask)} is private" do
        assert Madam.private_network?(unquote(ip), unquote(netmask))
      end
    end

    for {ip, netmask} <- public_ipsv4 do
      test "#{Macro.to_string(ip)}/#{Macro.to_string(netmask)} is public" do
        refute Madam.private_network?(unquote(ip), unquote(netmask))
      end
    end

    for {ip, netmask} <- private_ipsv6 do
      test "#{Macro.to_string(ip)}/#{Macro.to_string(netmask)} is private" do
        assert Madam.private_network?(unquote(ip), unquote(netmask))
      end
    end
  end
end
