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
end

