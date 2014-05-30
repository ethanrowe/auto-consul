require 'thread'

module AutoConsul
  module Runner
    INITIAL_VERIFY_SLEEP = 0.1
    SLEEP_INTERVAL = 2
    RETRIES = 5

    class AgentProcess
      attr_reader :args
      attr_reader :exit_code
      attr_reader :pid
      attr_reader :status
      attr_reader :thread
      attr_reader :stop_queue
      attr_reader :stop_thread

      def initialize args
        @args = args.dup.freeze
        @callbacks = {}
      end

      def on_up &action
        register_callback :up, &action
      end

      def on_down &action
        register_callback :down, &action
      end

      def launch!
        set_status :starting
        @thread = Thread.new do
          Thread.current.abort_on_exception = true
          run_agent
        end
      end

      def run_agent
        handle_signals!
        @pid = spawn(*(['consul', 'agent'] + args), :pgroup => true)
        result = Process.waitpid2(@pid)
        @exit_code = result[1].exitstatus
        set_status :down
      end

      def handle_signals!
        if @stop_queue.nil?
          @stop_queue = Queue.new
          @stop_thread = Thread.new do
            while true
              @stop_queue.pop
              stop!
            end
          end
          ['INT', 'TERM'].each do |sig|
            Signal.trap(sig) do
              @stop_queue << sig
            end
          end
        end
        nil
      end

      VALID_VERIFY_STATUSES = [nil, :starting]

      def verify_up!
        sleep INITIAL_VERIFY_SLEEP
        tries = 0
        while VALID_VERIFY_STATUSES.include?(status) and tries < RETRIES
          sleep SLEEP_INTERVAL ** tries if tries > 0
          if system('consul', 'info')
            set_status :up
          else
            tries += 1
          end
        end
      end

      def on_stopping &action
        register_callback :stopping, &action
      end

      VALID_STOP_STATUSES = [nil, :starting, :up, :stopping]
      STOP_SIGNAL = "SIGINT"

      def stop!
        raise "The consul agent is not running (no pid)" if pid.nil?
        raise "The consul agent is not running (status #{status.to_s})." unless VALID_STOP_STATUSES.include? status
        set_status :stopping
        Process.kill STOP_SIGNAL, pid
      end

      def register_callback on_status, &action
        (@callbacks[on_status] ||= []) << action
      end

      def run!
        launch!
        verify_up!
        status
      end

      def wait
        if (t = thread).nil?
          raise "The consul agent has not started within this runner."
        end
        t.join
        exit_code
      end

      def while_up &action
        on_up do |obj|
          thread = Thread.new { action.call obj }
          obj.on_stopping {|x| thread.kill }
          obj.on_down {|x| thread.kill }
        end
      end

      def run_callbacks on_status
        if callbacks = @callbacks[on_status]
          callbacks.each do |callback|
            callback.call self
          end
        end
      end

      def set_status new_status
        @status = new_status
        run_callbacks new_status
        new_status
      end
    end

    def self.joining_runner(agent_args, remote_ip=nil)
      runner = AgentProcess.new(agent_args)
      if not remote_ip.nil?
        runner.on_up {|a| join remote_ip}
      end
      runner
    end

    def self.verify_running pid
      RETRIES.times do |i|
        sleep SLEEP_INTERVAL + (SLEEP_INTERVAL * i)
        return true if system('consul', 'info')
      end
      return false
    end

    def self.join remote_ip
      system('consul', 'join', remote_ip)
    end

    def self.pick_joining_host hosts
      # Lets randomize this later.
      hosts[0].data
    end

    def self.agent_runner identity, bind_ip, expiry, local_state, registry
      remote_ip = pick_joining_host(registry.agents.members(expiry))
      joining_runner(['-bind', bind_ip,
                      '-data-dir', local_state.data_path,
                      '-node', identity], remote_ip)
    end

    def self.server_runner identity, bind_ip, expiry, local_state, registry
      members = registry.servers.members(expiry)
      remote_ip = members.size > 0 ? pick_joining_host(members) : nil

      args = ['-bind', bind_ip, '-data-dir', local_state.data_path, '-node', identity, '-server']
      args << '-bootstrap' if members.size < 1

      joining_runner(args, remote_ip)
    end
  end
end
