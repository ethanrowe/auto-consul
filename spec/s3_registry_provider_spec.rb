require 'spec-helper'

shared_examples_for 'a heartbeat emitter' do
  it 'should write a TIMESTAMP-IDENTIFIER entry under the key prefix with the payload as data.' do
    objects.should_receive(:[]).with(File.join(path, "#{stamp}-#{identity}")).and_return(obj = double)
    obj.should_receive(:write).with(payload = "Some payload data #{double.to_s}")
    subject.heartbeat! identity, payload, expiry
  end
end

shared_examples_for 'has valid members' do |locator_pairs|
  let :member_pairs do
    locator_pairs.collect do |time_sym, identifier|
      [send(time_sym), identifier]
    end
  end

  it 'gets appropriate identifier and timestamp per member' do
    m = subject.members(expiry).collect {|mem| [mem.time, mem.identifier]}
    m.should == member_pairs
  end

  it 'does not read object data if not requested' do
    member_pairs.each do |pair|
      s3_cache[pair].should_not_receive(:read)
    end

    subject.members(expiry).each {|mem| :amazing}
  end

  it 'exposes object data through the :data method' do
    m = subject.members(expiry).collect {|mem| mem.data}
    m.should == member_pairs.collect {|p| s3_cache[p].read}
  end
end

describe AutoConsul::Cluster::Registry::S3Provider do
  let(:provider) { AutoConsul::Cluster::Registry::S3Provider }
  let(:bucket) { "bucket-#{self.object_id.to_s}" }
  let(:path) { "#{self.object_id.to_s}/foo/bar" }
  let(:uri) { "s3://#{bucket}/#{path}" }

  context 'retrieved via AutoConsul::Cluster.get_provider_for_uri' do
    it 'should be the provider for an s3:// URL' do
      AutoConsul::Cluster.get_provider_for_uri(uri).should be_a provider
    end

    it 'should be instantiated with the uri string as URI instance' do
      provider.should_receive(:new).with(URI(uri))
      AutoConsul::Cluster.get_provider_for_uri(uri)
    end
  end

  describe 'given a URI instance' do
    subject { provider.new URI(uri) }

    it 'should get the bucket name from the URI host' do
      subject.bucket_name.should == bucket
    end

    it 'should get the key prefix from the URI path' do
      subject.key_prefix.should == path
    end

    it 'should get the bucket object using the bucket name and the AWS SDK' do
      AWS::S3.stub(:new).and_return(s3 = double)
      s3.should_receive(:buckets).with.and_return(buckets = double)
      buckets.should_receive(:[]).with(bucket).and_return(bucket_object = double)
      subject.bucket.should == bucket_object
    end

    context 'with a bucket' do
      let(:bucket_object) { double }
      let(:objects) { double }
      let(:time) do
        t = Time.now.utc
        Time.utc t.year, t.month, t.day, t.hour, t.min, t.sec, 0
      end
      let(:expiry) { 120.to_i }
      let(:check_time) { time - expiry }

      before do
        subject.stub(:bucket).with.and_return(bucket_object)
        bucket_object.stub(:objects).with.and_return(objects)
      end

      describe 'the heartbeat method' do
        let(:identity) { "#{self.object_id.to_s}-identifier" }
        let(:stamp) { time.dup.utc.strftime('%Y%m%d%H%M%S') }
        
        before do
          t = time
          Time.stub(:now).with.and_return(t)
        end

        describe 'with no expiry' do
          let(:expiry) { nil }

          before do
            objects.should_not_receive(:with_prefix)
            bucket.should_not_receive(:delete_if)
            objects.should_not_receive(:delete_if)
            bucket.should_not_receive(:delete)
            objects.should_not_receive(:delete)
          end

          it_should_behave_like 'a heartbeat emitter'
        end

        describe 'with an expiry' do
          let(:expiry) { 145.to_i }
          let(:check_time) { time.dup.utc - expiry }

          let :pre_expiration do
            double "S3Object", :key => File.join(path, "#{(check_time - 1).strftime('%Y%m%d%H%M%S')}-foo")
          end

          let :on_expiration do
            double "S3Object", :key => File.join(path, "#{check_time.strftime('%Y%m%d%H%M%S')}-bar")
          end

          let :post_expiration do
            double "S3Object", :key => File.join(path, "#{(check_time + 1).strftime('%Y%m%d%H%M%S')}-baz")
          end

          before do
            objects.should_receive(:with_prefix).with(path).and_return(with_pre = double)
            with_pre.should_receive(:delete_if) do |&block|
              block.call(pre_expiration).should be_true
              block.call(post_expiration).should be_false
              block.call(on_expiration).should be_true
            end
          end

          it_should_behave_like 'a heartbeat emitter'
        end
      end

      describe 'and no heartbeats' do
        before do
          objects.should_receive(:with_prefix).with(path).and_return(collection = double)
          # Doesn't yield, and thus is "empty".
          collection.should_receive(:each).and_return(collection)
        end
      end

      describe 'and heartbeats' do
        let(:s3_cache) { {} }
        let :deletes do
          key_source.find_all {|pair| pair[0] <= check_time}.collect do |pair|
            s3_cache[pair]
          end
        end

        before do
          with_pre = objects.should_receive(:with_prefix).with(path).and_return(with_prefix_each = double)
          with_prefix_each = with_prefix_each.should_receive(:each).with
          key_source.inject(with_prefix_each) do |o, pair|
            s3_cache[pair] = double("S3Object",
                                    :key => File.join(path, "#{pair[0].strftime('%Y%m%d%H%M%S')}-#{pair[1]}"),
                                    :read => pair[1])
            o.and_yield(s3_cache[pair])
          end

          with_prefix_each.and_return(with_prefix_each) if key_source.size < 1
        end

        before do
          if deletes.size > 0
            objects.should_receive(:delete).with(deletes)
          else
            objects.should_not_receive(:delete)
          end
        end

        describe 'past expiration' do
          let(:earliest) { (check_time - 10).utc }
          let(:early) { (check_time - 5).utc }
          let(:max_time) { check_time.dup.utc }

          let :key_source do
            [[earliest, 'earliest'],
             [early, 'early'],
             [max_time, 'expiry']]
          end

          it 'should have an empty members list' do
            subject.members(expiry).should == []
          end
        end

        describe 'that are live' do
          let(:valid_early) { (check_time + 1).utc }
          let(:valid_late) { (time - 1).utc }

          describe 'only' do
            let :key_source do
              [[valid_early, 'both'],
              [valid_early, 'early_only'],
              [valid_late, 'both'],
              [valid_late, 'late_only']]
            end

            it_should_behave_like 'has valid members', [
                [:valid_early, 'early_only'],
                [:valid_late, 'both'],
                [:valid_late, 'late_only']]
          end

          describe 'mixed with expired heartbeats' do
            let(:expired_early) { (check_time - 10).utc }
            let(:expired_late) { check_time.dup.utc }

            let :key_source do
              [[expired_early, 'expired_and_valid'],
               [expired_early, 'expired_early'],
               [expired_late, 'expired_late'],
               [expired_late, 'check_time_and_valid'],
               [valid_early, 'both'],
               [valid_early, 'early_only'],
               [valid_early, 'expired_and_valid'],
               [valid_late, 'both'],
               [valid_late, 'check_time_and_valid'],
               [valid_late, 'late_only']]
            end

            it_should_behave_like 'has valid members', [
                [:valid_early, 'early_only'],
                [:valid_early, 'expired_and_valid'],
                [:valid_late, 'both'],
                [:valid_late, 'check_time_and_valid'],
                [:valid_late, 'late_only']]
          end
        end
      end
    end
  end
end

