require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'
require_relative 'mixin_esxi_opts'

module VagrantPlugins
  module ESXi
    module Command
      class Create < Vagrant.plugin("2", :command)
        include ::VagrantPlugins::ESXi::Util::ESXCLI
        include MixinESXiOpts

        def self.synopsis
          "Create VMWare ESXi network (port groups)"
        end

        def execute
          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant network create <name>"
            o.separator ""

            build_esxi_opts(o)

            o.on("--vlan ID", "VLAN ID (defaults to 0).") do |l|
              @vlan = l
            end

            o.on("--vswitch VSWITCH", "vSwitch name (defaults to '#{esxi_config.default_vswitch}').") do |s|
              @vswitch = s
            end
          end

          argv = parse_options(opts)
          return if !argv

          @name = argv.shift
          return unless @name
          @vswitch ||= esxi_config.default_vswitch
          @vlan ||= 0

          provider_configs_in_env? ? create_network_with_env : create_network_with_config(esxi_config)

          0
        end

        protected
          # Use ESXi configuration from vagrant environment
          def create_network_with_env
            provider_configs_in_env.each { |config| create_network_with_config(config) }
          end

          # Use supplied ESXi configuration
          def create_network_with_config(esxi_config)
            raise_missing!(:esxi_hostname)
            esxi_config.esxi_password ||= ask_password
            create_network(esxi_config)
          end

          def create_network(config)
            @env.ui.info "Creating network '#{@name}' (VLAN##{@vlan}, vSwitch '#{@vswitch}') on ESXi host '#{config.esxi_hostname}'"

            connect_ssh(config) do
              unless create_port_group(@name, @vswitch, @vlan)
                raise Errors::ESXiError, message: "Failed to create network '#{@name}' (VLAN##{@vlan}, vSwitch '#{@vswitch}')"
              end
            end
          end
      end
    end
  end
end
