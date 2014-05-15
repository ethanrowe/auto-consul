module AutoConsul
  module Runner
    SLEEP_INTERVAL = 2
    RETRIES = 5

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
