require 'spec-helper'

def mock_output name
  File.open(File.join(File.dirname(__FILE__), name), 'r') do |f|
    f.read
  end
end

shared_examples_for 'a running cli agent' do
  it 'should be running' do
    expect(subject).to be_running
  end

  it 'should be a running cli agent' do
    expect(subject).to be_agent
  end
end

describe AutoConsul::RunState::CLIProvider do
  subject do
    AutoConsul::RunState::CLIProvider.new
  end

  let :consul_fail do
    c = subject.should_receive(:system).with do |cmd, opts|
      cmd.should == 'consul info'
    end
    c.and_return false
    c
  end

  let :consul_call do
    subject.should_receive(:system) do |cmd, opts|
      cmd.should == 'consul info'
      opts[:out].write(output)
    end
  end

  describe 'with no running consul' do
    before do
      consul_fail
    end

    it 'should not be running' do
      expect(subject).not_to be_running
    end

    it 'should not be a running cli agent' do
      expect(subject).not_to be_agent
    end

    it 'should not be a server' do
      expect(subject).not_to be_server
    end
  end

  describe 'with running consul' do
    before do
      consul_call
    end

    describe 'as normal agent' do
      let(:output) { mock_output 'agent-output.txt' }

      it_should_behave_like 'a running cli agent'

      it 'should not be a server' do
        expect(subject).not_to be_server
      end
    end

    describe 'as server' do
      let(:output) { mock_output 'server-output.txt' }

      it_should_behave_like 'a running cli agent'

      it 'should be a server' do
        expect(subject).to be_server
      end
    end
  end
end
