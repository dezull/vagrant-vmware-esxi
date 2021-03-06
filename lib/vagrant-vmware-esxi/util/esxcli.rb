require "net/ssh"

module VagrantPlugins
  module ESXi
    module Util
      module ESXCLI
        PORT_GROUP_HEADER_RE = /^(?<name>-+)\s+(?<vswitch>-+)\s+(?<clients>-+)\s+(?<vlan>-+)$/
        PORT_GROUP_NAME_IN_VMSVC_RE = /^\s*name = "(?<name>.+)",\s*$/
        DATASTORE_PATH_IN_ESXCLI_RE = /.+"(?<path>.+)".+/
        VM_INFO_IN_VMSVC_RE = /(?<id>\d+)\s+(?<name>\S+)\s+\[(?<datastore>\S+)\]\s+(?<vmx>\S+)\s+(?<type>\S+)\s+(?<vmx_version>\S+).*/
        VSWITCH_PORTGROUPS_IN_ESXCLI_RE = /^\s+Portgroups: (?<portgroups>.+)$/

        def has_vswitch?(vswitch)
          r = exec_ssh("esxcli network vswitch standard list | "\
                       "grep -E '^#{vswitch}$'")

          r.exitstatus == 0
        end

        def create_vswitch(vswitch)
          r = exec_ssh("esxcli network vswitch standard add -v '#{vswitch}'")

          r.exitstatus == 0
        end

        # @return [Hash] Map of port group to :vswitch, :clients (running VMs) and :vlan 
        def get_port_groups
          cmd = "esxcli network vswitch standard portgroup list"
          r = exec_ssh(cmd)
          if r.exitstatus != 0
            raise_ssh_error(cmd, r, "Unable to get port groups")
          end

          # Active Client is *running* VM attached to the network

          # Parse output such as:
          # Name                           Virtual Switch    Active Clients  VLAN ID
          # -----------------------------  ----------------  --------------  -------
          # Management Network             vSwitch0                       1        0
          # Internal                       Internal                       0        0

          lines = r.strip.split("\n")
          max_name_len, max_vswitch_len, max_clients_len, max_vlan_len =
            lines[1].match(PORT_GROUP_HEADER_RE).captures.map(&:length)

          lines[2..-1].map do |line|
            m = line.match(/^
              (?<name>.{#{max_name_len}})\s+
              (?<vswitch>.{#{max_vswitch_len}})\s+
              (?<clients>.{#{max_clients_len}})\s+
              (?<vlan>.{#{max_vlan_len}})
            $/x)

            [m[:name].strip, {
              vswitch: m[:vswitch].strip,
              clients: m[:clients].to_i,
              vlan: m[:vlan].to_i
            }]
          end.to_h
        end

        def get_vm_info(matcher)
          key, value = matcher.to_a.first
          get_vms.find { |vm| vm[key] == value }
        end

        # Port groups that are attached to any VM
        def get_active_port_group_names
          port_group_names = []
          vmids = get_vms.map { |vm| vm[:id] }

          vmids.each do |vmid|
            cmd = "vim-cmd vmsvc/get.networks #{vmid}"
            r = exec_ssh(cmd)

            next if r.match? "Unable to find a VM corresponding"

            if r.exitstatus != 0
              raise_ssh_error(cmd, r, "Unable to get port groups for vm '#{vmid}'")
            end

            r.strip.split("\n").each do |line|
              if matches = PORT_GROUP_NAME_IN_VMSVC_RE.match(line)
                port_group_name = matches[:name]
                port_group_names << port_group_name unless port_group_names.include?(port_group_name)
              end
            end
          end

          port_group_names
        end

        def get_vswitch_port_group_names(vswitch)
          cmd = "esxcli network vswitch standard list -v '#{vswitch}'"
          r = exec_ssh(cmd)
          if r.exitstatus != 0
            raise_ssh_error(cmd, r, "Unable to get port groups for vswitch '#{vswitch}'")
          end

          if m = VSWITCH_PORTGROUPS_IN_ESXCLI_RE.match(r.strip)
            m[:portgroups].split(", ")
          end
        end

        def remove_vswitch(vswitch)
          r  = exec_ssh("esxcli network vswitch standard remove -v '#{vswitch}'")

          r.exitstatus == 0
        end

        def create_port_group(port_group, vswitch, vlan = 0)
          # Use vim-cmd instead of esxcli, as it can add port group to vlan in a go
          r = exec_ssh("vim-cmd hostsvc/net/portgroup_add "\
                       "'#{vswitch}' "\
                       "'#{port_group}' "\
                       "#{vlan}")

          r.exitstatus == 0
        end

        def remove_port_group(port_group, vswitch)
          r  = exec_ssh("esxcli network vswitch standard portgroup remove -p '#{port_group}' -v '#{vswitch}'")

          r.exitstatus == 0
        end

        def get_vmrc_uri
          machine = vagrant_env[:machine]
          hostname = machine.provider_config.esxi_hostname
          cmd = "vim-cmd vmsvc/acquireticket #{machine.id} mks | "\
                "sed 's/localhost/#{hostname}/' | " \
                "grep -E '^vmrc://'"
          r = exec_ssh(cmd)
          if r.exitstatus != 0
            raise_ssh_error(cmd, r, "Unable to get VMRC URI")
          end

          r.strip
        end

        def get_datastore_path(datastore_name)
          cmd = "vim-cmd hostsvc/datastore/info '#{datastore_name}' | grep path"
          r = exec_ssh(cmd)
          if r.exitstatus != 0
            raise_ssh_error(cmd, r, "Unable to find datastore #{datastore_name}")
          end

          m = DATASTORE_PATH_IN_ESXCLI_RE.match(r.strip)
          unless m && m[:path]
            raise Errors::ESXiError, message: "Unable to find datastore #{datastore_name}"
          end

          m[:path]
        end

        def get_vms
          cmd = "vim-cmd vmsvc/getallvms"
          r = exec_ssh(cmd)
          if r.exitstatus != 0
            raise_ssh_error(cmd, r, "Unable to get VMs")
          end

          ss = StringScanner.new(r.strip)
          vms = []
          while m = ss.scan_until(VM_INFO_IN_VMSVC_RE)
            vms << VM_INFO_IN_VMSVC_RE.names.reduce({}) do |memo, k|
              key = k.to_sym
              memo[key] = ss[key]
              memo
            end
          end
          vms
        end

        def clone_vm_disk(source_vm_name, target_vm_name, datastore_path)
          vm_info = get_vm_info(name: source_vm_name.to_s)
          src_disk = "#{datastore_path}/#{vm_info[:vmx].gsub(/vmx$/, "vmdk")}"
          target_disk = "#{datastore_path}/#{target_vm_name}/#{target_vm_name}.vmdk"
          r = exec_ssh("rm #{datastore_path}/#{target_vm_name}/*.vmdk && "\
                       "vmkfstools -d thin -i '#{src_disk}' '#{target_disk}'")

          r.exitstatus == 0
        end

        def destroy_vm(id)
          r = exec_ssh("vim-cmd vmsvc/destroy #{id}")
          if r.exitstatus != 0
            raise_ssh_error(cmd, r, "Unable to get port groups")
          end
        end

        def destroy_vm_by_name(name)
          if vm = get_vm_info(name: name)
            destroy_vm(vm[:id])
          else
            false
          end
        end

        # Client should probably never use this, add a method in this module instead
        def exec_ssh(cmd)
          @_ssh.exec!(cmd).tap do |r|
            @logger.debug("exec_ssh: `#{cmd}`\n#{r}") if @logger
          end
        end

        # @param [Hash|VagrantPlugins::ESXi::Config] env_or_config
        def connect_ssh(env_or_config = @env)
          @vagrant_env = env_or_config unless env_or_config.is_a?(::VagrantPlugins::ESXi::Config)
          config = @vagrant_env ? @vagrant_env[:machine].provider_config : env_or_config

          if @_ssh
            raise Errors::ESXiError, message: "SSH session already established"
          end

          error = nil
          r = nil
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
            begin
              r = yield
            rescue => e
              error = e
            end
            @_ssh = nil
          end
        rescue ::Net::SSH::Exception => e
          raise Errors::ESXiError, message: "SSH Error:\n" + e.full_message
        ensure
          raise error if error
          r
        end

        private

          def raise_ssh_error(cmd, result, message)
            if @logger
              @logger.error { "`#{cmd}` exited with #{result.exitstatus}. Output:\n  #{result}" }
            end
            raise Errors::ESXiError, message: message
          end

          def vagrant_env
            raise if @vagrant_env.nil?
            @vagrant_env
          end
      end
    end
  end
end
