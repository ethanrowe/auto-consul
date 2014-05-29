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
        @pid = spawn(*(['consul', 'agent'] + args))
        result = Process.waitpid2(@pid)
        @exit_code = result[1].exitstatus
        set_status :down
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

    def self.launch_and_join(agent_args, remote_ip=nil)
      pid = spawn(*(['consul', 'agent'] + agent_args))

      # We really need to check that is running, but later.
      return nil unless verify_running(pid)

      if not remote_ip.nil?
        join remote_ip
      end

      pid
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

    def self.run_agent! identity, bind_ip, expiry, local_state, registry
      remote_ip = pick_joining_host(registry.agents.members(expiry))
      pid = launch_and_join(['-bind', bind_ip,
                             '-data-dir', local_state.data_path,
                             '-node', identity], remote_ip)
      Process.wait pid
    end

    def self.run_server! identity, bind_ip, expiry, local_state, registry
      members = registry.servers.members(expiry)
      remote_ip = members.size > 0 ? pick_joining_host(members) : nil

      args = ['-bind', bind_ip, '-data-dir', local_state.data_path, '-node', identity, '-server']
      args << '-bootstrap' if members.size < 1

      pid = launch_and_join(args, remote_ip)

      Process.wait pid unless pid.nil?
    end
  end
end
