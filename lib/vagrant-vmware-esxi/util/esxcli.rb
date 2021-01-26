module VagrantPlugins
  module ESXi
    module Util
      module ESXCLI
        PORT_GROUP_HEADER_RE = /^(?<name>-+)\s+(?<vswitch>-+)\s+(?<clients>-+)\s+(?<vlan>-+)$/
        PORT_GROUP_NAME_IN_VMSVC_RE = /^\s*name = "(?<name>.+)",\s*$/
        DATASTORE_PATH_IN_ESXCLI_RE = /.+"(?<path>.+)".+/
        VM_INFO_IN_VMSVC_RE = /(?<id>\d+)\s+(?<name>\S+)\s+\[(?<datastore>\S+)\]\s+(?<vmx>\S+)\s+(?<type>\S+)\s+(?<vmx_version>\S+).*/

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
          r = exec_ssh("esxcli network vswitch standard portgroup list")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get port groups"
          end

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

        def get_vm_info(vm_name)
          r = exec_ssh("vim-cmd vmsvc/getallvms | grep -E '\\s+#{vm_name}\\s+'")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get VM info"
          end

          m = VM_INFO_IN_VMSVC_RE.match(r.strip)
          m.named_captures
        end

        # Port groups that are attached to any VM
        def get_active_port_group_names
          r = exec_ssh("vim-cmd vmsvc/getallvms | cut -d' ' -f1 | tail -n +2")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get active port groups"
          end

          port_group_names = []

          r.strip.split("\n").each do |vmid|
            r = exec_ssh("vim-cmd vmsvc/get.networks #{vmid}")
            if r.exitstatus != 0
              raise Errors::ESXiError, message: "Unable to get port groups for vm '#{vmid}'"
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
          r = exec_ssh("esxcli network vswitch standard list -v '#{vswitch}' | "\
                       "grep Portgroups | "\
                       'sed -E "s/^\s+Portgroups: //"')

          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to get port groups for vswitch '#{vswitch}'"
          end

          r.strip.split(", ")
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

        def get_datastore_path(datastore_name)
          r = exec_ssh("vim-cmd hostsvc/datastore/info '#{datastore_name}' | grep path")
          if r.exitstatus != 0
            raise Errors::ESXiError, message: "Unable to find datastore #{datastore_name}"
          end

          m = DATASTORE_PATH_IN_ESXCLI_RE.match(r.strip)
          unless m && m[:path]
            raise Errors::ESXiError, message: "Unable to find datastore #{datastore_name}"
          end

          m[:path]
        end

        def clone_vm_disk(source_vm_name, target_vm_name, datastore_path)
          vm_info = get_vm_info(source_vm_name)
          src_disk = "#{datastore_path}/#{vm_info["vmx"].gsub(/vmx$/, "vmdk")}"
          target_disk = "#{datastore_path}/#{target_vm_name}/#{target_vm_name}.vmdk"
          r = exec_ssh("rm #{datastore_path}/#{target_vm_name}/*.vmdk && "\
                       "vmkfstools -d thin -i '#{src_disk}' '#{target_disk}'")

          r.exitstatus == 0
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
