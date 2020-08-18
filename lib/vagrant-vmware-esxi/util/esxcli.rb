module VagrantPlugins
  module ESXi
    module Util
      module ESXCLI
        PORT_GROUP_HEADER_RE = /^(?<name>-+)\s+(?<vswitch>-+)\s+(?<clients>-+)\s+(?<vlan>-+)$/

        # @return [Hash] Map of port group to :vswitch, :clients and :vlan 
        def get_port_groups(ssh)
          r = ssh.exec!("esxcli network vswitch standard portgroup list")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get port groups"
          end

          # Parse output such as:
          # Name                           Virtual Switch    Active Clients  VLAN ID
          # -----------------------------  ----------------  --------------  -------
          # Management Network             vSwitch0                       1        0
          # Internal                       Internal                       0        0

          lines = r.split("\n")
          max_name_len, max_vswitch_len, max_clients_len, max_vlan_len =
            lines[1].match(PORT_GROUP_HEADER_RE).captures.map(&:length)

          lines[2..-1].map do |line|
            m = line.match(/^
              (?<name>.{#{max_name_len}})\s+
              (?<vswitch>.{#{max_vswitch_len}})\s+
              (?<clients>.{#{max_clients_len}})\s+
              (?<vlan>.{#{max_vlan_len}})
            $/x)

            [m[:name].strip, {
              vswitch: m[:vswitch].strip,
              clients: m[:clients].to_i,
              vlan: m[:vlan].to_i
            }]
          end.to_h
        end

        def vswitch_port_groups(ssh, vswitch)
          r = ssh.exec!("esxcli network vswitch standard list -v '#{vswitch}' | "\
                        "grep Portgroups | "\
                        'sed -E "s/^\s+Portgroups: //"')

          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get port groups for vswitch '#{vswitch}'"
          end

          r.strip.split(", ")
        end

        def remove_vswitch(ssh, vswitch)
          r  = ssh.exec!("esxcli network vswitch standard remove -v '#{vswitch}'")

          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to remove vswitch '#{vswitch}'"
          end
        end

        def remove_port_group(ssh, port_group, vswitch)
          r  = ssh.exec!("esxcli network vswitch standard portgroup remove -p '#{port_group}' -v '#{vswitch}'")

          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to remove port group '#{port_group}'"
          end
        end
      end
    end
  end
end
