require "optparse"
require 'vagrant-vmware-esxi/util/esxcli'

module VagrantPlugins
  module ESXi
    module Command
      class VMRC < Vagrant.plugin("2", :command)
        include Vagrant::Util::SafePuts

        def self.synopsis
          "get VMware Remote Console URL"
        end

        def execute
          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant vmrc [name]"
          end

          # Parse the options
          argv = parse_options(opts)
          return if !argv

          with_target_vms(argv) do |machine|
            vmrc_uri = machine.action(:vmrc_uri)[:result]
            safe_puts "#{machine.name} (#{machine.provider_name}):"
            safe_puts vmrc_uri
            safe_puts
          end

          0
        end
      end
    end
  end
end
