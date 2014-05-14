module AutoConsul::RunState
  class CLIProvider
    AGENT_MASK = 0b1
    SERVER_MASK = 0b10

    def check_run_state
      result = 0
      r, w = IO.pipe
      if system("consul info", :out => w)
        w.close
        result = flags_from_output r
        r.close
      end
      result
    end

    def flags_from_output stream
      consul_block = false
      result = 0
      stream.each do |line|
        if line =~ /^consul:\s/
          consul_block = true
          result = AGENT_MASK
          break
        end
      end

      if consul_block
        stream.each do |line|
          # Exit condition from consul block
          break if line !~ /^\s+/

          if line =~ /^\s+server\s+=\s+true/
            result |= SERVER_MASK
            break
          end
        end
      end
      result
    end

    def run_state
      if @run_state.nil?
        @run_state = check_run_state
      end
      @run_state
    end

    def agent?
      (run_state & AGENT_MASK) > 0
    end

    def server?
      (run_state & SERVER_MASK) > 0
    end

    def running?
      run_state > 0
    end
  end
end
