require 'net/ssh'
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
          ssh { destroy_networks }
          @app.call(env)
        end

        def destroy_networks
          destroy_unused_port_groups if @env[:machine].provider_config.destroy_unused_port_groups
          destroy_unused_vswitches if @env[:machine].provider_config.destroy_unused_vswitches
        end

        def destroy_unused_port_groups
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying unused port groups that were created automatically...")

          all_port_groups = get_port_groups(@ssh)
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
          remove_port_group(@ssh, port_group, vswitch)
        end

        def destroy_unused_vswitches
          @env[:ui].info I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                message: "Destroying unused vSwitches that were created automatically...")

          @logger.debug("all port groups: #{created_networks["vswitches"].inspect}")
          created_networks["vswitches"].each do |vswitch|
            if vswitch_port_groups(@ssh, vswitch).empty?
              destroy_unused_vswitch(vswitch)
            end
          end
        end

        def destroy_unused_vswitch(vswitch)
          @env[:ui].detail I18n.t("vagrant_vmware_esxi.vagrant_vmware_esxi_message",
                                  message: "Destroying vswitch '#{vswitch}'")
          remove_vswitch(@ssh, vswitch)
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
      end
    end
  end
end
