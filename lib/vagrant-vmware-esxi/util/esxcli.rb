module VagrantPlugins
  module ESXi
    module Util
      module ESXCLI
        def get_vmrc_uri
          machine = @env[:machine]
          hostname = machine.provider_config.esxi_hostname
          r = exec_ssh("vim-cmd vmsvc/acquireticket #{machine.id} mks | "\
                       "sed 's/localhost/#{hostname}/' | " \
                       "grep -E '^vmrc://'")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get VMRC URI"
          end

          r.strip
        end

        # Client should probably never use this, add a method in this module instead
        def exec_ssh(cmd)
          @_ssh.exec!(cmd).tap do |r|
            @logger.debug("exec_ssh: `#{cmd}`\n#{r}") if @logger
          end
        end

        def connect_ssh
          if @_ssh
            raise Errors::ESXiError, message: "SSH session already established"
          end

          config = @env[:machine].provider_config
          Net::SSH.start(
            config.esxi_hostname,
            config.esxi_username,
            password: config.esxi_password,
            port: config.esxi_hostport,
            keys: config.local_private_keys,
            timeout: 20,
            number_of_password_prompts: 0,
            non_interactive: true
          ) do |ssh|
            @_ssh = ssh
            r = yield
            @_ssh = nil
            r
          end
        end
      end
    end
  end
end
