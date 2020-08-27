require 'log4r'

module VagrantPlugins
  module ESXi
    module Action
      class VMRC_URI
        include Util::ESXCLI

        def initialize(app, env)
          @app    = app
          @logger = Log4r::Logger.new('vagrant_vmware_esxi::action::vmrc_uri')
        end

        def call(env)
          @env = env
          connect_ssh do
            state = env[:machine_state].to_s
            if state == "running" || state == "powered_on"
              uri = get_vmrc_uri
              env[:result] = uri && uri.strip
            else
              env[:result] = "Not powered on"
            end
          end
          @app.call(env)
        end
      end
    end
  end
end
