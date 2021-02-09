require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'
require_relative 'mixin_esxi_opts'

module VagrantPlugins
  module ESXi
    module Command
      class List < Vagrant.plugin("2", :command)
        include ::VagrantPlugins::ESXi::Util::ESXCLI
        include MixinESXiOpts

        def self.synopsis
          "List VMWare ESXi networks (port groups)"
        end

        def execute
          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant network list"
            o.separator ""

            build_esxi_opts(o)
          end

          argv = parse_options(opts)
          return if !argv

          provider_configs_in_env? ? list_networks_with_env : list_networks_with_config(esxi_config)

          0
        end

        protected
          # Use ESXi configuration from vagrant environment
          def list_networks_with_env
            provider_configs_in_env.each { |config| list_networks_with_config(config) }
          end

          # Use supplied ESXi configuration
          def list_networks_with_config(esxi_config)
            raise_missing!(:esxi_hostname)
            esxi_config.esxi_password ||= ask_password
            list_networks(esxi_config)
          end

          def list_networks(config)
            connect_ssh(config) do
              port_groups = get_port_groups
              max_name_length = port_groups.keys.map { |name| name.to_s.size }.max
              max_vswitch_length = port_groups.values.map { |f| f[:vswitch].size }.max

              list = ["#{'Port group'.ljust(max_name_length)} #{'vSwitch'.ljust(max_vswitch_length)} VLAN"]
              list += port_groups.map do |name, f|
                "#{name.to_s.ljust(max_name_length)} #{f[:vswitch].ljust(max_vswitch_length)} #{f[:vlan]}"
              end

              @env.ui.info(list.join("\n"))
            end
          end
      end
    end
  end
end
