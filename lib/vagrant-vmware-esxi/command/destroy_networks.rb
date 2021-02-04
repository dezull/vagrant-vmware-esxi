require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'

module VagrantPlugins
  module ESXi
    module Command
      class DestroyNetworks < Vagrant.plugin("2", :command)
        include ::VagrantPlugins::ESXi::Util::ESXCLI

        IP_RE = '(\d{1,3}\.){3}\d{1,3}'
        IP_PREFIX_RE = '\d{1,2}'

        def self.synopsis
          "destroy all VMWare ESXi networks (port groups) and vSwitches that were created automatically"
        end

        def execute
          @force = false

          esxi_config = ::VagrantPlugins::ESXi::Config.new.tap do |c|
            c.esxi_password = nil
            c.finalize!
          end

          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant destroy-networks"
            o.separator ""
            o.separator "This command will try to use ESXi configuration found in existing Vagrant environment. "\
                        "If you are running this outside an environment, you should provide --esxi-* configuration."\
                        "It also assumes network names that follow the pattern {vSwitchName}-{network-address}-{network-mask}"\
                        "are created automatically by this plugin."
            o.separator ""
            o.separator "Options:"
            o.separator ""

            o.on("--esxi-user USER", "ESXi SSH user.") do |u|
              esxi_config.esxi_username = u
            end

            o.on("--esxi-password PASSWORD", "ESXi SSH password. If required and not provided, it will prompt.") do |p|
              esxi_config.esxi_password = p
            end

            o.on("--esxi-host HOST", "ESXi host.") do |h|
              esxi_config.esxi_hostname = h
            end

            o.on("--esxi-port PORT", "ESXi SSH port.") do |p|
              esxi_config.esxi_hostport = p
            end

            o.on("-f", "--force", "Destroy without confirmation.") do |f|
              @force = f
            end
          end

          argv = parse_options(opts)
          return if !argv

          if @env.root_path
            destroy_networks_with_env
          else
            debug_config = esxi_config.instance_variables_hash.slice("esxi_hostname", "esxi_hostport", "esxi_username")
            @env.ui.warn "Couldn't not find ESXi configuration in any Vagrant environment, using this instead: #{debug_config}"
            destroy_networks_with_config(esxi_config)
          end

          0
        end

        protected

          # Use ESXi configuration from vagrant environment
          def destroy_networks_with_env
            machines = []
            with_target_vms { |machine| machines << machine }
            # Get unique ESXi configurations
            machines
              .filter { |machine| machine.provider_name == :vmware_esxi }
              .uniq { |machine| machine.provider_config }
              .each do |machine|
                destroy_networks_with_config(machine.provider_config)
              end
          end

          # Use supplied ESXi configuration
          def destroy_networks_with_config(esxi_config)
            raise Errors::ESXiError, message: "--esxi-host is required" if esxi_config.esxi_hostname.nil?

            esxi_config.esxi_password ||= @env.ui.ask(
              "#{esxi_config.esxi_username}@#{esxi_config.esxi_hostname} password: ",
              echo: false
            )

            destroy_networks(esxi_config)
          end

          def destroy_networks(config)
            @env.ui.info "Destroying networks on ESXi host '#{config.esxi_hostname}'"

            connect_ssh(config) do
              destroy_unused_auto_port_groups(config.default_vswitch)
            end
          end

          def destroy_unused_auto_port_groups(vswitch)
            active_port_groups = get_active_port_group_names
            vswitch = Regexp.escape(vswitch)
            auto_port_group_re ||= /^#{vswitch}-#{IP_RE}-#{IP_PREFIX_RE}$/

            get_port_groups.each do |name, port_group|
              if auto_port_group_re.match?(name) && !active_port_groups.include?(name)
                destroy_unused_port_group(name, port_group[:vswitch])
              end
            end
          end

          def destroy_unused_port_group(port_group, vswitch)
            if @force || confirm_destroy_port_group?(port_group)
              @env.ui.detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                     message: "Destroying port group '#{port_group}'")
              unless remove_port_group(port_group, vswitch)
                raise Errors::ESXiError, message: "Unable to remove port group '#{port_group}'"
              end
            end
          end

          def confirm_destroy_port_group?(port_group)
            answer = @env.ui.ask(I18n.t("vagrant_vmware_esxi.commands.destroy_networks.one.confirmation", network: port_group))
            answer.downcase == I18n.t("vagrant_vmware_esxi.commands.destroy_networks.confirmed")
          end
      end
    end
  end
end
