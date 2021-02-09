require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'
require_relative 'mixin_esxi_opts'

module VagrantPlugins
  module ESXi
    module Command
      class Destroy < Vagrant.plugin("2", :command)
        include ::VagrantPlugins::ESXi::Util::ESXCLI
        include MixinESXiOpts

        def self.synopsis
          "Destroy VMWare ESXi network (port group)"
        end

        def execute
          @force = false

          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant network destroy <name>"
            o.separator ""

            build_esxi_opts(o)

            o.on("--vswitch VSWITCH", "vSwitch name (defaults to '#{esxi_config.default_vswitch}').") do |s|
              @vswitch = s
            end

            o.on("-f", "--force", "Destroy without confirmation.") do |f|
              @force = f
            end
          end

          argv = parse_options(opts)
          return if !argv

          @name = argv.shift
          return unless @name
          @vswitch ||= esxi_config.default_vswitch

          provider_configs_in_env? ? destroy_network_with_env : destroy_network_with_config(esxi_config)

          0
        end

        protected
          # Use ESXi configuration from vagrant environment
          def destroy_network_with_env
            provider_configs_in_env.each { |config| destroy_network_with_config(config) }
          end

          # Use supplied ESXi configuration
          def destroy_network_with_config(esxi_config)
            raise_missing!(:esxi_hostname)
            esxi_config.esxi_password ||= ask_password
            destroy_network(esxi_config)
          end

          def destroy_network(config)
            @env.ui.info "Destroying network '#{@name}' (vSwitch '#{@vswitch}') on ESXi host '#{config.esxi_hostname}'"

            connect_ssh(config) do
              if @force || confirm_destroy_port_group?
                unless remove_port_group(@name, @vswitch)
                  raise Errors::ESXiError, message: "Failed to remove network '#{@name}' (vSwitch '#{@vswitch}')"
                end
              end
            end
          end

          def confirm_destroy_port_group?
            answer = @env.ui.ask(I18n.t("vagrant_vmware_esxi.commands.destroy_networks.one.confirmation", network: @name))
            answer.downcase == I18n.t("vagrant_vmware_esxi.commands.destroy_networks.confirmed")
          end
      end
    end
  end
end
