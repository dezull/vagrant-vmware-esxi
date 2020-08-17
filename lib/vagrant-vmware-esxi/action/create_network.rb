require 'net/ssh'

module VagrantPlugins
  module ESXi
    module Action
      MAX_VLAN = 4094
      VLANS = Array.new(MAX_VLAN) { |i| i + 1 }.freeze

      # Automatically create network (Port group/VLAN) per subnet
      #
      # For example, when a box given 192.168.1.10/24, create 192.168.1.0/24 port group.
      # Then, when another box is given 192.168.1.20/24, use the same port group from
      # the previous one.
      #
      # TODO: REMOVE
      # config.vm.network 'private_network', ip: '192.168.10.170', netmask: '255.255.255.0',
      #   esxi__vswitch: "Internal Switch"
      class CreateNetwork
        def initialize(app, env)
          @app = app
        end

        def call(env)
          @env = env
          create_network
          @app.call(env)
        end

        def create_network
          ssh do
            @env[:machine].config.vm.networks.each do |type, network_options|
              next if type != :private_network && type != :public_network
              set_network_configs(type, network_options)
              create_vswitch(network_options)
              create_port_group(network_options)
            end

          end
          # TODO create port groups

          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                               message: "networks: #{@env[:machine].config.vm.networks}")
        end

        def ssh
          config = @env[:machine].provider_config
          Net::SSH.start(config.esxi_hostname, config.esxi_username,
                         password:                   config.esxi_password,
                         port:                       config.esxi_hostport,
                         keys:                       config.local_private_keys,
                         timeout:                    20,
                         number_of_password_prompts: 0,
                         non_interactive:            true
                        ) do |ssh|
                          @ssh = ssh
                          yield
                        end
        end

        def exec_ssh(cmd)
          @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                 message: "exec_ssh: #{cmd}")

          @ssh.exec!(cmd)
        end

        def set_network_configs(type, network_options)
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                               message: "networks: #{type} #{network_options}")

          # FIXME move to configuration validation
          private_network_configs = [:esxi__vswitch, :dhcp] & network_options.keys
          if type == :public_network && private_network_configs.any?
            raise Errors::ESXiError,
              message: "Setting #{private_network_configs.join(', ')} not allowed for `public_network`."
          end

          network_options[:esxi__vswitch] = network_options[:esxi__vswitch] || default_vswitch

          network_options[:esxi__port_group] =
            if network_options[:type] == "dhcp" || !network_options[:ip]
              default_port_group(network_options[:esxi__vswitch])
            else
              network_options[:netmask] ||= 24

              ip = IPAddr.new("#{network_options[:ip]}/#{network_options[:netmask]}")
              "#{network_options[:esxi__vswitch]}-#{ip.to_s}-#{ip.prefix}"
            end
        end

        def create_vswitch(network_options)
          r = exec_ssh(
            "esxcli network vswitch standard list -v #{network_options[:esxi__vswitch]} ||"\
            "esxcli network vswitch standard add -v #{network_options[:esxi__vswitch]}")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable create new vSwitch."
          end
        end

        def create_port_group(network_options)
          r = exec_ssh("esxcli network vswitch standard portgroup list")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get port groups"
          end

          # Parse output such as:
          # Name                           Virtual Switch    Active Clients  VLAN ID
          # -----------------------------  ----------------  --------------  -------
          # Management Network             vSwitch0                       1        0
          # Internal                       Internal                       0        0

          lines = r.split("\n")
          max_name_len = lines[1].match(/^-+ /)[0].size - 1

          port_group_vlan_map = lines[2..-1].map do |line|
            m = line.match(/(?<name>^.{#{max_name_len}}).*(?<vlan>\d+$)/)
            [m[:name].strip, m[:vlan].to_i]
          end.to_h

          # port group already created
          return if port_group_vlan_map[network_options[:esxi__port_group]]

          # VLAN 0 is bridged to physical NIC by default
          vlan_ids = port_group_vlan_map.values.uniq.sort - [0]
          vlan = (VLANS - vlan_ids).first
          unless vlan
            raise Errors::ESXiError,
              message: "No more VLAN (max: #{MAX_VLAN}) to assign to the port group"
          end

          # Use vim-cmd instead of esxcli, as it can add port group to vlan in a go
          r = exec_ssh("vim-cmd hostsvc/net/portgroup_add "\
                       "#{network_options[:esxi__vswitch]} "\
                       "#{network_options[:esxi__port_group]} "\
                       "#{vlan}")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Cannot create port group "\
              "`#{network_options[:esxi__port_group]}`, VLAN #{vlan}"
          end
        end

        def default_vswitch
          @default_vswitch ||=
            exec_ssh("esxcli network vswitch standard list | head -n1").tap do |r|
              if r.exitstatus != 0
                raise Errors::ESXiError, message: "Unable to get default vSwitch."
              end
            end.strip
        end

        def default_port_group(vswitch)
          r = exec_ssh(
            "esxcli network vswitch standard list -v #{vswitch} |"\
            "grep Portgroups | sed 's/^\s*Portgroups: //' | sed 's/, /\n/g'")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get default port group."
          end
          port_groups = r.split("\n")

          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                               message: "Port groups for #{vswitch}: #{port_groups}")
          port_groups.first
        end
      end
    end
  end
end
