require 'spec-helper'

shared_examples_for 'a consul agent run' do |method_name, registry_name, join_flag, args|
  it 'properly launches consul agent' do
    members = []
    members << member if join_flag

    registry.should_receive(registry_name).with.and_return(reg = double)
    reg.should_receive(:members).with(expiry).and_return(members)

    expected_args = (['consul', 'agent', '-bind', ip, '-data-dir', data_dir, '-node', identity] + args).collect do |e|
                      if e.instance_of? Symbol
                        send e
                      else
                        e
                      end
                    end

    AutoConsul::Runner.should_receive(:spawn).with(*expected_args).and_return(agent_pid = double)

    # consul info retries to verify that it's running.
    AutoConsul::Runner.should_receive(:system).with('consul', 'info').and_return(false, false, true)

    AutoConsul::Runner.should_receive(:sleep).with(2)
    AutoConsul::Runner.should_receive(:sleep).with(4)
    AutoConsul::Runner.should_receive(:sleep).with(6)

    if join_flag
      AutoConsul::Runner.should_receive(:system).with('consul', 'join', remote_ip).and_return(true)
    end

    Process.should_receive(:wait).with(agent_pid)

    callable = AutoConsul::Runner.method(method_name)
    callable.call(identity, ip, expiry, local_state, registry)
  end
end

describe AutoConsul::Runner::AgentProcess do
  let(:args) do
    (1..3).collect do |i|
      double("MockParam#{i.to_s}").to_s
    end
  end

  subject { AutoConsul::Runner::AgentProcess.new args }

  describe "launch! method" do
    let(:thread) { double('AgentThread') }
    let(:pid) { double('AgentPid') }
    let(:exit_code) { 2.to_i }

    before do
      # This sucks, but what are you gonna do?  It needs to be in a separate
      # thread so the waitpid2 call doesn't block the main process.
      subject.should_receive(:spawn).with(['consul', 'agent'] + args).and_return(pid)
      process_status = double('ProcessStatus', :pid => pid,
                                               :exitstatus => exit_code)
      Process.should_receive(:waitpid2).with(pid).and_return([pid, process_status])
      Thread.should_receive(:new) do |&block|
        # The status should be :starting before invoking the thread.
        expect(subject.status).to eq(:starting)
        block.call
        # The block is what moves it to a status of :down.
        # And sets the pid and exit code.
        expect(subject.status).to eq(:down)
        expect(subject.pid).to eq(pid)
        expect(subject.exit_code).to eq(exit_code)
        thread
      end
    end

    it 'should invoke "agent consul" with given args and wait on the result' do
      expect(subject.thread).to be_nil
      expect(subject.pid).to be_nil
      expect(subject.status).to be_nil
      expect(subject.exit_code).to be_nil
      subject.launch!
      expect(subject.thread).to be(thread)
    end

    # it should blow up if called with status other than nil, :down.
  end

  describe "verify_up! method" do
    describe 'when check succeeds' do
      before do
        subject.should_receive(:sleep).with(0.1)
        subject.should_receive(:system).with('consul', 'info').and_return(false, false, false, true)
        subject.should_receive(:sleep).with(2)
        subject.should_receive(:sleep).with(4)
        subject.should_receive(:sleep).with(8)
      end

      it 'sets status to :up' do
        subject.verify_up!
        expect(subject.status).to eq(:up)
      end

      describe 'with callbacks' do
        before do
          subject.on_up do |obj|
            subject.callback_a! obj
            expect(subject.status).to eq(:up)
          end

          subject.on_up do |obj|
            subject.callback_b! obj
            expect(subject.status).to eq(:up)
          end

          subject.should_receive(:callback_a!).with(subject)
          subject.should_receive(:callback_b!).with(subject)
        end

        it 'invokes up callbacks with itself as parameter' do
          subject.verify_up!
        end
      end
    end

    describe 'when check fails' do
      before do
        subject.should_receive(:sleep).with(0.1)
        subject.should_receive(:system).with('consul', 'info').and_return(false, false, false, false, false)
        subject.should_receive(:sleep).with(2)
        subject.should_receive(:sleep).with(4)
        subject.should_receive(:sleep).with(8)
        subject.should_receive(:sleep).with(16)
      end
      
      it 'leaves the status alone' do
        subject.should_not_receive(:set_status)
        subject.verify_up!
        expect(subject.status).to be_nil
      end

      describe 'with callbacks' do
        before do
          subject.on_up do |obj|
            subject.callback_a! obj
          end

          subject.on_up do |obj|
            subject.callback_b! obj
          end

          subject.should_not_receive(:callback_a!)
          subject.should_not_receive(:callback_b!)
        end

        it 'does not invoke callbacks at all' do
          subject.verify_up!
        end
      end

      # it should blow up if called with status other than :starting, :up
    end
  end
end

describe AutoConsul::Runner do
  let(:ip) { "192.168.50.101" }
  let(:remote_ip) { "192.168.50.102" }
  let(:member) { double("ClusterMember", :identity => 'foo', :time => double, :data => remote_ip) }
  let(:agents_list) { [] }
  let(:servers_list) { [] }
  let(:identity) { "id-#{double.object_id}" }
  let(:data_dir) { "/var/lib/consul/#{double.object_id}" }
  let(:local_state) { double("FileSystemState", :data_path => data_dir) }
  let(:registry) { double("Registry", :agents => double("S3Provider"),
                                      :servers => double("S3Provider")) }

  let(:expiry) { 120.to_i }

  before do
    registry.agents.stub(:agents).with(expiry).and_return(agents_list)
    registry.servers.stub(:servers).with(expiry).and_return(servers_list)
  end

  describe :run_agent! do
    it_behaves_like 'a consul agent run', :run_agent!, :agents, true, []
  end

  describe :run_server! do
    describe 'with empty server registry' do
      # consul agent -bind 192.168.50.100 -data-dir /opt/consul/server/data -node vagrant-server -server -bootstrap
      it_behaves_like 'a consul agent run', :run_server!, :servers, false, ['-server', '-bootstrap']
    end

    describe 'with other servers in registry' do
      # consul agent -bind 192.168.50.100 -data-dir /opt/consul/server/data -node vagrant-server -server
      # consul join some_ip

      it_behaves_like 'a consul agent run', :run_server!, :servers, true, ['-server']
    end
  end
end
