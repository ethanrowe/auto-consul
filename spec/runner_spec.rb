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
    AutoConsul::Runner.should_receive(:system).with(
      ['consul', 'info']).and_return(false, false, true)

    AutoConsul::Runner.should_receive(:sleep).with(2)
    AutoConsul::Runner.should_receive(:sleep).with(4)
    AutoConsul::Runner.should_receive(:sleep).with(6)

    if join_flag
      AutoConsul::Runner.should_receive(:system).with(
        ['consul', 'join', remote_ip]).and_return(true)
    end

    Process.should_receive(:wait).with(agent_pid)

    callable = AutoConsul::Runner.method(method_name)
    callable.call(identity, ip, expiry, local_state, registry)
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
