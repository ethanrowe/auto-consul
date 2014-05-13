require 'spec-helper'

shared_examples_for 'a server' do
  it 'should use "PATH/server" for data path' do
    subject.data_path.should == File.join(tempdir.path 'server')
  end

  it 'should be true for server?' do
    subject.should be_server
  end

  it 'should be false for agent?' do
    subject.should_not be_agent
  end
end

shared_examples_for 'an agent' do
  it 'should use "PATH/agent" for data path' do
    subject.data_path.should == File.join(tempdir.path 'agent')
  end

  it 'should be false for server?' do
    subject.should_not be_server
  end

  it 'should be true for agent?' do
    subject.should be_agent
  end
end

tempdir_context AutoConsul::Local do
  subject { AutoConsul::Local.bind_to_path path }

  let(:path) { tempdir.path }

  context 'given a non-existent path' do
    let(:path) { tempdir.path 'faux', 'state', 'directory' }

    it 'should create the desired path' do
      File.directory?(subject.path).should be_true
    end
  end

  it 'should use "PATH/mode" for mode_path' do
    subject.mode_path.should == File.join(path, 'mode')
  end

  context 'set to server mode' do
    before do
      subject.set_server!
    end

    it 'should enter "server" in mode file' do
      File.open(tempdir.path('mode'), 'r').read.should == 'server'
    end

    it_should_behave_like 'a server'
  end

  context 'set to agent mode' do
    before do
      subject.set_agent!
    end

    it 'should enter "agent" in mode file' do
      File.open(tempdir.path('mode'), 'r').read.should == 'agent'
    end

    it_should_behave_like 'an agent'
  end

  context 'given a server mode file' do
    before do
      File.open(File.join(path, 'mode'), 'w') {|f| f.write 'server'}
    end

    it_should_behave_like 'a server'
  end

  context 'given an agent mode file' do
    before do
      File.open(File.join(path, 'mode'), 'w') {|f| f.write 'agent'}
    end

    it_should_behave_like 'an agent'
  end

  context 'given a bogus mode file' do
    before do
      File.open(File.join(path, 'mode'), 'w') {|f| f.write 'shmerver'}
    end

    it 'should have a nil mode' do
      subject.mode.should be_nil
    end

    it 'should be false for server?' do
      subject.should_not be_server
    end

    it 'should be false for agent?' do
      subject.should_not be_agent
    end

    it 'should have a nil data_path' do
      subject.data_path.should be_nil
    end
  end
end

