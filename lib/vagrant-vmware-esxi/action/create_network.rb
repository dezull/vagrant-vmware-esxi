require 'net/ssh'

module VagrantPlugins
  module ESXi
    module Action
      MAX_VLAN = 4094
      VLANS = Array.new(MAX_VLAN) { |i| i + 1 }.freeze
      PORT_GROUP_HEADER_RE = /^(?<name>-+)\s+(?<vswitch>-+)\s+(?<clients>-+)\s+(?<vlan>-+)$/

      # Automatically create network (Port group/VLAN) per subnet
      #
      # For example, when a box given 192.168.1.10/24, create 192.168.1.0/24 port group.
      # Then, when another box is given 192.168.1.20/24, use the same port group from
      # the previous one.
      #
      # Example configuration:
      #   config.vm.network "private_network", ip: "192.168.10.170", netmask: "255.255.255.0",
      #
      # This will create port group '{vSwitchName}-192.168.10.0-24'.
      #
      # You can also use manual configurations for the vSwitch and the port group, such as:
      #   config.vm.network "private_network", ip: "192.168.10.170", netmask: "255.255.255.0",
      #     esxi__vswitch: "Internal Switch", esxi__port_group: "Internal Network"
      #
      # Notes:
      # 1. If you specify only esxi__port_group, a new port group will be created on the default_vswitch if
      # not already created. If you specify only esxi__vswitch, the default_port_group will be used, and
      # it will error if there's a mismatch. In this case, you should probably specify both.
      # 2. If you specify both esxi__port_group and esxi__vswitch, a new port group will be created
      # on that vSwitch if not already created.
      #
      # For (1) and (2), the vSwitch will also be created if not already created. In any case,
      # if esxi__port_group already exists, the esxi__vswitch is ignored (not in the VMX file).
      class CreateNetwork
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_vmware_esxi::action::create_network')
        end

        def call(env)
          @env = env
          @default_vswitch = env[:machine].provider_config.default_vswitch
          @default_port_group = env[:machine].provider_config.default_port_group
          create_network
          @app.call(env)
        end

        def create_network
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Default network on Adapter 1: vSwitch: #{@default_vswitch}, "\
                                "port group: #{@default_port_group}")
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Creating other networks...")

          ssh do
            @env[:machine].config.vm.networks.each.with_index do |(type, network_options), index|
              adapter = index + 2
              next if type != :private_network && type != :public_network
              set_network_configs(adapter, type, network_options)
              create_vswitch(network_options)
              create_port_group(network_options)

              details = "vSwitch: #{network_options[:esxi__vswitch]}, "\
                "port group: #{network_options[:esxi__port_group]}"
              @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                      message: "Adapter #{adapter}: #{details}")
            end
          end
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
          @logger.debug("exec_ssh: #{cmd}")
          @ssh.exec!(cmd)
        end

        def set_network_configs(adapter, type, network_options)
          # TODO Does this matter? we don't really care where default_vswitch is bridged to anyway
          # Assume public_network is using provider_config default_vswitch and default_port_group
          private_network_configs = [:esxi__vswitch, :esxi__port_group, :dhcp] & network_options.keys
          if type == :public_network && private_network_configs.any?
            raise Errors::ESXiError,
              message: "Setting #{private_network_configs.join(', ')} not allowed for `public_network`."
          end

          custom_vswitch = true if network_options[:esxi__vswitch]
          dhcp = network_options[:type] == "dhcp" || !network_options[:ip]
          network_options[:esxi__vswitch] ||= @default_vswitch
          network_options[:netmask] ||= 24 unless dhcp

          network_options[:esxi__port_group] ||=
            if custom_vswitch || dhcp
              @default_port_group
            else
              # Use the address to generate the port_group name
              ip = IPAddr.new("#{network_options[:ip]}/#{network_options[:netmask]}")
              "#{network_options[:esxi__vswitch]}-#{ip.to_s}-#{ip.prefix}"
            end
        end

        def create_vswitch(network_options)
          @logger.info("Creating vSwitch '#{network_options[:esxi__vswitch]}' if not yet created")
          r = exec_ssh(
            "esxcli network vswitch standard list -v '#{network_options[:esxi__vswitch]}' || "\
            "esxcli network vswitch standard add -v '#{network_options[:esxi__vswitch]}'")
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
          max_name_len, max_vswitch_len, max_clients_len, max_vlan_len =
            lines[1].match(PORT_GROUP_HEADER_RE).captures.map(&:length)

          port_groups = lines[2..-1].map do |line|
            m = line.match(/^
              (?<name>.{#{max_name_len}})\s+
              (?<vswitch>.{#{max_vswitch_len}})\s+
              (?<clients>.{#{max_clients_len}})\s+
              (?<vlan>.{#{max_vlan_len}})
            $/x)

            [m[:name].strip, { vswitch: m[:vswitch].strip, vlan: m[:vlan].to_i }]
          end.to_h
          @logger.debug("Port groups: #{port_groups}")

          if port_group = port_groups[network_options[:esxi__port_group]]
            # port group already created
            unless port_group[:vswitch] == network_options[:esxi__vswitch]
              raise Errors::ESXiError, message: "Existing port group '#{network_options[:esxi__port_group]}' "\
                "must be in vSwitch '#{network_options[:esxi__vswitch]}'"
            end

            return
          end

          # VLAN 0 is bridged to physical NIC by default
          vlan_ids = port_groups.values.map { |v| v[:vlan] }.uniq.sort - [0]
          vlan = (VLANS - vlan_ids).first
          unless vlan
            raise Errors::ESXiError,
              message: "No more VLAN (max: #{MAX_VLAN}) to assign to the port group"
          end

          vswitch = network_options[:esxi__vswitch] || @default_vswitch
          @logger.info("Creating port group #{network_options[:esxi__port_group]} on vSwitch '#{vswitch}'")
          # Use vim-cmd instead of esxcli, as it can add port group to vlan in a go
          r = exec_ssh("vim-cmd hostsvc/net/portgroup_add "\
                       "'#{vswitch}' "\
                       "'#{network_options[:esxi__port_group]}' "\
                       "#{vlan}")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Cannot create port group "\
              "`#{network_options[:esxi__port_group]}`, VLAN #{vlan}"
          end
        end
      end
    end
  end
end
