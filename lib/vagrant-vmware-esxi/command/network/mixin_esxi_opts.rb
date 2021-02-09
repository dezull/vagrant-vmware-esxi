require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'
require 'vagrant-vmware-esxi/config'
require 'io/console'

module VagrantPlugins
  module ESXi
    module Command
      module MixinESXiOpts
        def build_esxi_opts(o)
          @_esxi_config = ::VagrantPlugins::ESXi::Config.new.tap do |c|
            c.esxi_password = nil
            c.finalize!
          end

          o.separator "This command will try to use ESXi configuration found in existing Vagrant environment. "\
                      "If you are running this outside an environment, you should provide --esxi-* options."
          o.separator ""
          o.separator "Options:"
          o.separator ""

          o.on("--esxi-username USER", "ESXi SSH user.") do |u|
            esxi_config.esxi_username = u
          end

          o.on("--esxi-password PASSWORD", "ESXi SSH password. If required and not provided, it will prompt.") do |p|
            esxi_config.esxi_password = p
          end

          o.on("--esxi-hostname HOST", "ESXi host.") do |h|
            esxi_config.esxi_hostname = h
          end

          o.on("--esxi-hostport PORT", "ESXi SSH port.") do |p|
            esxi_config.esxi_hostport = p
          end

          o.on("--global", "Don't use Vagrant environment, use --esxi-* options instead.") do
            @global = true
          end
        end

        def ask_password
          @env.ui.ask("#{esxi_config.esxi_username}@#{esxi_config.esxi_hostname} password: ",
                     echo: false)
        end

        def provider_configs_in_env?
          if @env.root_path && !@global
            true
          else
            debug_config = esxi_config.instance_variables_hash.slice("esxi_hostname", "esxi_hostport", "esxi_username")
            @env.ui.warn "Couldn't not find any ESXi configuration in any Vagrant environment, using this instead: #{debug_config}"
            false
          end
        end

        def provider_configs_in_env
            machines = []
            with_target_vms { |machine| machines << machine }
            # Get unique ESXi configurations
            machines
              .filter { |machine| machine.provider_name == :vmware_esxi }
              .uniq { |machine| machine.provider_config }
              .map { |machine| machine.provider_config }
        end

        def raise_missing!(config_key)
          arg = config_key.to_s.gsub("_", "-")
          raise Errors::ESXiError, message: "--#{arg} is required" if esxi_config.try(config_key).nil?
        end

        def esxi_config
          @_esxi_config
        end
      end
    end
  end
end
