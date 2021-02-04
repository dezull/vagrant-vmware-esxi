require "vagrant/action/builtin/confirm"

module VagrantPlugins
  module ESXi
    module Action
      class DestroyUnusedNetworksConfirm < Confirm
        def initialize(app, env)
          force_key = :force_confirm_destroy_networks
          message = I18n.t("vagrant_vmware_esxi.commands.destroy_networks.all.confirmation")

          super(app, env, message, force_key, allowed: ["y", "n", "Y", "N"])
        end
      end
    end
  end
end
