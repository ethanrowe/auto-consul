require 'rspec'
require 'fileutils'
require 'tempfile'
require 'auto-consul'

module AutoConsulTest
  # A wrapper for a temporary directory.
  #
  # While initialization will create a temporary directory, it is the
  # caller's responsibility to clean things up.
  class Tempdir
    def initialize
      @path = File.expand_path(Dir.mktmpdir)
    end

    # Helper that joins `paths` to the temporary directory for easy
    # temporary-directory-internal path generation.
    #
    # Call it with no arguments to get the temporary directory itself.
    def path(*paths)
      if paths.size > 0
        File.join @path, *paths
      else
        @path
      end
    end
  end
end

module RSpec::Core::DSL
  def tempdir_context(*args, &block)
    describe(*args) do
      let(:tempdir) { AutoConsulTest::Tempdir.new }

      after do
        ::FileUtils.remove_entry tempdir.path
      end

      instance_eval(&block)
    end
  end
end

