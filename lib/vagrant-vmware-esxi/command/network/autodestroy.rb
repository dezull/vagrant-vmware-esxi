require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'
require_relative 'mixin_esxi_opts'

module VagrantPlugins
  module ESXi
    module Command
      class AutoDestroy < Vagrant.plugin("2", :command)
        include ::VagrantPlugins::ESXi::Util::ESXCLI
        include MixinESXiOpts

        IP_RE = '(\d{1,3}\.){3}\d{1,3}'
        IP_PREFIX_RE = '\d{1,2}'

        def self.synopsis
          "destroy all VMWare ESXi networks (port groups) and vSwitches that were created automatically"
        end

        def execute
          @force = false

          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant network destroy"
            o.separator ""

            o.separator "It assumes network names that follow the pattern {vSwitchName}-{network-address}-{network-mask}"\
                        "are created automatically by this plugin."
            build_esxi_opts(o)

            o.on("-f", "--force", "Destroy without confirmation.") do |f|
              @force = f
            end
          end

          argv = parse_options(opts)
          return if !argv

          provider_configs_in_env? ? destroy_networks_with_env : destroy_networks_with_config(esxi_config)

          0
        end

        protected

          # Use ESXi configuration from vagrant environment
          def destroy_networks_with_env
            provider_configs_in_env.each { |config| destroy_networks_with_config(config) }
          end

          # Use supplied ESXi configuration
          def destroy_networks_with_config(esxi_config)
            raise_missing!(:esxi_hostname)
            esxi_config.esxi_password ||= ask_password
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
