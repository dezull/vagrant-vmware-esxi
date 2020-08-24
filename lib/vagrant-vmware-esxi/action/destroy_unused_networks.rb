require 'vagrant-vmware-esxi/util/esxcli'

module VagrantPlugins
  module ESXi
    module Action
      class DestroyUnusedNetworks
        include Util::ESXCLI

        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new('vagrant_vmware_esxi::action::destroy_unused_networks')
        end

        def call(env)
          @env = env
          @vmid = env[:machine].id
          connect_ssh { destroy_networks }
          @app.call(env)
        end

        def destroy_networks
          destroy_unused_port_groups if @env[:machine].provider_config.destroy_unused_port_groups
          destroy_unused_vswitches if @env[:machine].provider_config.destroy_unused_vswitches
        end

        def destroy_unused_port_groups
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying unused port groups that were created automatically...")

          all_port_groups = get_port_groups
          @logger.debug("all port groups: #{all_port_groups.inspect}")
          created_networks["port_groups"].each do |port_group|
            found = all_port_groups[port_group]
            if found[:clients] == 0
              destroy_unused_port_group(port_group, found[:vswitch])
            end
          end
        end

        def destroy_unused_port_group(port_group, vswitch)
          @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying port group '#{port_group}'")
          unless remove_port_group(port_group, vswitch)
            raise Errors::ESXiError, message: "Unable to remove port group '#{port_group}'"
          end
        end

        def destroy_unused_vswitches
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying unused vSwitches that were created automatically...")

          @logger.debug("all port groups: #{created_networks["vswitches"].inspect}")
          created_networks["vswitches"].each do |vswitch|
            if get_vswitch_port_groups(vswitch).empty?
              destroy_unused_vswitch(vswitch)
            end
          end
        end

        def destroy_unused_vswitch(vswitch)
          @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                  message: "Destroying vswitch '#{vswitch}'")
          unless remove_vswitch(vswitch)
            raise Errors::ESXiError, message: "Unable to remove vswitch '#{vswitch}'"
          end
        end

        def created_networks
          @created_networks ||= (
            file = @env[:machine].data_dir.join("networks")
            if file.exist?
              JSON.parse(File.read(file))
            else
              { "port_groups" => [], "vswitches" => [] }
            end
          )
        end
      end
    end
  end
end
