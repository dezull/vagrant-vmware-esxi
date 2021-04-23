require 'log4r'

module VagrantPlugins
  module ESXi
    module Action
      # This action set the IP address  (do the config.vm_network settings...)
      class SetGuestName
        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new('vagrant_vmware_esxi::action::set_guest_name')
        end

        def call(env)
          set_guest_name(env)
          @app.call(env)
        end

        def set_guest_name(env)
          machine = env[:machine]
          config = env[:machine].provider_config

          # Set desired_guest_name
          if machine.config.vm.hostname.nil? && config.guest_name.nil?
            #  Nothing set, so generate our own
            desired_guest_name = config.guest_name_prefix.strip
            desired_guest_name << `hostname`.partition('.').first.strip
            desired_guest_name << '-'
            desired_guest_name << `whoami`.gsub!(/[^0-9A-Za-z]/, '').strip
            desired_guest_name << '-'
            base = File.basename machine.env.cwd.to_s
            desired_guest_name << base
          elsif !machine.config.vm.hostname.nil? && config.guest_name.nil?
            desired_guest_name = machine.config.vm.hostname.dup
          else
            # Both are set, or only guest_name. So, we'll choose guest_name.
            desired_guest_name = config.guest_name.strip
          end
          desired_guest_name = desired_guest_name[0..252].gsub(/_/,'-').gsub(/[^0-9A-Za-z\-\.]/i, '').strip
          config.saved_guest_name = desired_guest_name
          @logger.info("vagrant-vmware-esxi, set_guest_name: #{desired_guest_name}")
        end
      end
    end
  end
end
