require 'vagrant-vmware-esxi/util/esxcli'

module VagrantPlugins
  module ESXi
    module Action
      class DestroyUnusedNetworks
        include Util::ESXCLI

        def initialize(app, env)
          @app = app
          @scope = env[:scope]
          @logger = Log4r::Logger.new('vagrant_vmware_esxi::action::destroy_unused_networks')
        end

        def call(env)
          @env = env
          @vmid = env[:machine].id
          connect_ssh { destroy_networks }
          @app.call(env)
        end

        def destroy_networks
          # Destroy unused port groups that were created by this `vagrant up`
          destroy_unused_port_groups if @env[:machine].provider_config.destroy_unused_port_groups
          destroy_unused_vswitches if @env[:machine].provider_config.destroy_unused_vswitches
        end

        def destroy_unused_port_groups
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying unused port groups that were created automatically...")

          all_port_groups = get_port_groups
          active_port_groups = get_active_port_group_names
          @logger.debug("all port groups: #{all_port_groups.inspect}")
          @logger.debug("active port groups: #{active_port_groups}")
          @logger.debug("port groups to destroy: #{created_networks["port_groups"]}")
          created_networks["port_groups"].each do |port_group|
            found = all_port_groups[port_group]
            unless active_port_groups.include? port_group
              destroy_port_group(port_group, found[:vswitch])
            end
          end
        end

        def destroy_port_group(port_group, vswitch)
          @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying port group '#{port_group}'")
          unless remove_port_group(port_group, vswitch)
            @env[:ui].warn I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                   message: "Unable to remove port group '#{port_group}'. Probably already removed?")
          end
        end

        def destroy_unused_vswitches
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying unused vSwitches that were created automatically...")

          @logger.debug("all port groups: #{created_networks["vswitches"].inspect}")
          created_networks["vswitches"].each do |vswitch|
            if get_vswitch_port_group_names(vswitch).empty?
              destroy_unused_vswitch(vswitch)
            end
          end
        end

        def destroy_unused_vswitch(vswitch)
          @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                  message: "Destroying vswitch '#{vswitch}'")
          unless remove_vswitch(vswitch)
            @env[:ui].warn I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                   message: "Unable to remove vswitch '#{vswitch}'. Probably already removed?")
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
