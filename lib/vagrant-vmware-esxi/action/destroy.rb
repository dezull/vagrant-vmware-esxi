require 'log4r'
require 'net/ssh'
require 'vagrant-vmware-esxi/util/esxcli'

module VagrantPlugins
  module ESXi
    module Action
      # This action will Destroy VM. unregister and delete the VM from disk.
      class Destroy
        include Util::ESXCLI

        def initialize(app, _env)
          @app    = app
          @logger = Log4r::Logger.new('vagrant_vmware_esxi::action::destroy')
        end

        def call(env)
          @env = env
          connect_ssh { destroy(env) }
          @app.call(env)
        end

        def destroy(env)
          @logger.info('vagrant-vmware-esxi, destroy: start...')

          # Get config.
          machine = env[:machine]
          config = env[:machine].provider_config

          @logger.info("vagrant-vmware-esxi, destroy: machine id: #{machine.id}")
          @logger.info('vagrant-vmware-esxi, destroy: current state: '\
                       "#{env[:machine_state]}")

          destroyed = false
          if env[:machine_state].to_s == 'not_created'
            if config.destroy_vm_by_name
              env[:ui].warn I18n.t('vagrant_vmware_esxi.destroy_vm_by_name', name: config.saved_guest_name)
              destroyed = true if destroy_vm_by_name(config.saved_guest_name)
            end

            env[:ui].info I18n.t('vagrant_vmware_esxi.already_destroyed') unless destroyed
          elsif env[:machine_state].to_s != 'powered_off'
            raise Errors::ESXiError,
                  message: 'Guest VM should have been powered off...'
          else
            destroy_vm(machine.id)
            destroyed = true
          end

          if destroyed
            env[:ui].info I18n.t('vagrant_vmware_esxi.vagrant_vmware_esxi_message',
                                 message: 'VM has been destroyed...')
          end
        end
      end
    end
  end
end
