require 'spec-helper'

describe AutoConsul::Cluster do
  let(:uri) { "s3://some-bucket-#{double.object_id}/some/prefix/#{double.object_id}" }
  let(:servers_uri) { "#{uri}/servers" }
  let(:agents_uri) { "#{uri}/agents" }
  let(:registry_lookup) { AutoConsul::Cluster.should_receive(:get_provider_for_uri) }

  subject { AutoConsul::Cluster.new uri }

  it 'should get provider for */servers' do
    registry_lookup.once.with(servers_uri).and_return(provider = double("S3Provider"))
    expect(subject.servers).to equal(provider)
    expect(subject.servers).to equal(provider)
  end

  it 'should get provider for */agents' do
    registry_lookup.once.with(agents_uri).and_return(provider = double("S3Provider"))
    subject.agents
    expect(subject.agents).to equal(provider)
    expect(subject.agents).to equal(provider)
  end

  describe 'set_mode!' do
    let(:agents) { [] }
    let(:servers) { [] }
    let(:expiry) { double }
    let(:local_state) { double }

    before do
      subject.stub(:agents).and_return(agents_reg = double)
      agents_reg.stub(:members).with(expiry).and_return agents
      subject.stub(:servers).and_return(servers_reg = double)
      servers_reg.stub(:members).with(expiry).and_return servers
    end

    describe 'with no active servers' do
      before do
        # Default desired servers of 1.
        local_state.should_receive(:set_server!)
      end

      it 'should set_server! with no server count specified' do
        subject.set_mode! local_state, expiry
      end

      it 'should set_server! with a server count specified' do
        subject.set_mode! local_state, expiry, 2
      end
    end

    describe 'without enough active servers' do
      before do
        local_state.should_receive(:set_server!).with
        local_state.should_not_receive(:set_agent!)
      end

      it 'should set_server! given 1 server but wanting 3' do
        servers << double
        subject.set_mode! local_state, expiry, 3
      end

      it 'should set_server! given 3 servers but wanting 4' do
        servers << double
        servers << double
        servers << double
        subject.set_mode! local_state, expiry, 4
      end
    end

    describe 'with enough active servers' do
      before do
        servers << double
        local_state.should_receive(:set_agent!).with
        local_state.should_not_receive(:set_server!)
      end

      it 'should set_agent! given 1 server, wanting default' do
        subject.set_mode! local_state, expiry
      end

      it 'should set_agent! given 1 server, wanting 1' do
        subject.set_mode! local_state, expiry, 1
      end

      it 'should set_agent! given 3 servers, wanting 3' do
        servers << double
        servers << double
        subject.set_mode! local_state, expiry, 3
      end

      it 'should set_agent! given 3 servers, wanting 2' do
        servers << double
        servers << double
        subject.set_mode! local_state, expiry, 2
      end
    end
  end
end

