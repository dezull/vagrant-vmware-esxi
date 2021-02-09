require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'
require_relative 'mixin_esxi_opts'

module VagrantPlugins
  module ESXi
    module Command
      class Show < Vagrant.plugin("2", :command)
        include ::VagrantPlugins::ESXi::Util::ESXCLI
        include MixinESXiOpts

        def self.synopsis
          "Show VMWare ESXi network (port group)"
        end

        def execute
          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant network show <name>"
            o.separator ""

            build_esxi_opts(o)
          end

          argv = parse_options(opts)
          return if !argv

          @name = argv.shift
          return unless @name

          provider_configs_in_env? ? show_network_with_env : show_network_with_config(esxi_config)

          0
        end

        protected
          # Use ESXi configuration from vagrant environment
          def show_network_with_env
            provider_configs_in_env.each { |config| show_network_with_config(config) }
          end

          # Use supplied ESXi configuration
          def show_network_with_config(esxi_config)
            raise_missing!(:esxi_hostname)
            esxi_config.esxi_password ||= ask_password
            show_network(esxi_config)
          end

          def show_network(config)
            connect_ssh(config) do
              port_group = get_port_groups[@name]
              raise Errors::ESXiError, message: "Port group '#{@name}' not found" unless port_group

              @env.ui.info(<<~STR.strip)
                #{@name}
                  VLAN: #{port_group[:vlan]}
                  vSwitch: #{port_group[:vswitch]}
              STR
            end
          end
      end
    end
  end
end
