require 'optparse'

module VagrantPlugins
  module ESXi
    module Command
      class Root < Vagrant.plugin("2", :command)
        def self.synopsis
          "manages ESXI networks: create, destroy, etc"
        end

        def initialize(argv, env)
          super

          @main_args, @sub_command, @sub_args = split_main_and_subcommand(argv)

          @subcommands = Vagrant::Registry.new
          @subcommands.register(:create) do
            require_relative "create"
            Create
          end

          @subcommands.register(:destroy) do
            require_relative "destroy"
            Destroy
          end

          @subcommands.register(:list) do
            require_relative "list"
            List
          end

          @subcommands.register(:show) do
            require_relative "show"
            Show
          end

          @subcommands.register(:autodestroy) do
            require_relative "autodestroy"
            AutoDestroy
          end
        end

        def execute
          if @main_args.include?("-h") || @main_args.include?("--help")
            # Print the options for all the sub-commands.
            return options
          end

          # If we reached this far then we must have a subcommand. If not,
          # then we also just print the options and exit.
          command_class = @subcommands.get(@sub_command.to_sym) if @sub_command
          return options if !command_class || !@sub_command
          @logger.debug("Invoking command class: #{command_class} #{@sub_args.inspect}")

          # Initialize and execute the command class
          command_class.new(@sub_args, @env).execute
        end

        # Prints the help out for this command
        def options
          opts = OptionParser.new do |o|
            o.banner = "Usage: vagrant network <command> [<args>]"
            o.separator ""
            o.separator "Available subcommands:"

            # Add the available subcommands as separators in order to print them
            # out as well.
            keys = []
            @subcommands.each { |key, value| keys << key.to_s }

            keys.sort.each do |key|
              o.separator "     #{key}"
            end

            o.separator ""
            o.separator "For help on any individual command run `vagrant network COMMAND -h`"
          end

          @env.ui.info(opts.help, prefix: false)
        end
      end
    end
  end
end

