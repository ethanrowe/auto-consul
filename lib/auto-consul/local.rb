require 'fileutils'

module AutoConsul
  module Local
    class FileSystemState
      def initialize path
        unless File.directory? path
          FileUtils.mkdir_p path
        end

        @path = path
      end

      def path
        @path
      end

      def mode_path
        File.join(path, 'mode')
      end

      def set_server!
        set_mode 'server'
      end

      def set_agent!
        set_mode 'agent'
      end

      def set_mode mode
        File.open(mode_path, 'w') do |f|
          f.write mode
        end
      end

      VALID_MODES = {
        'agent' => 'agent',
        'server' => 'server',
      }

      def self.determine_mode mode_file
        if File.file? mode_file
          value = File.open(mode_file, 'r') {|f| f.read }
          VALID_MODES[value]
        else
          nil
        end
      end

      def mode
        if @mode.nil?
          @mode = self.class.determine_mode mode_path
        end
        @mode
      end

      def server?
        mode == 'server'
      end

      def agent?
        mode == 'agent'
      end

      def data_path
        if not (m = mode).nil?
          File.join(path, mode)
        else
          nil
        end
      end
    end

    def self.bind_to_path path
      FileSystemState.new path
    end
  end
end
