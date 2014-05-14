require 'aws-sdk'

module AutoConsul::Cluster::Registry
  class S3Provider < Provider
    class S3Member
      attr_reader :s3_object, :identifier, :time

      def initialize s3obj
        @s3_object = s3obj
        @time, @identifier = S3Provider.from_key_base(File.basename(s3obj.key))
        @data_read = false
      end

      def data
        if not @data_read
          @data = s3_object.read
          @data_read = true
        end
        @data
      end
    end

    def s3
      @s3 ||= self.class.get_s3
    end

    def self.get_s3
      AWS::S3.new
    end

    def bucket_name
      uri.host
    end

    def bucket
      @bucket ||= s3.buckets[bucket_name]
    end

    def key_prefix
      uri.path
    end

    def now
      Time.now
    end

    KEY_TIMESTAMP_FORMAT = '%Y%m%d%H%M%S'

    def self.write_stamp time
      time.dup.utc.strftime KEY_TIMESTAMP_FORMAT
    end

    def self.read_stamp stamp
      t = Time.strptime(stamp, KEY_TIMESTAMP_FORMAT)
      Time.utc(t.year, t.month, t.day, t.hour, t.min, t.sec, 0)
    end

    def self.to_key_base time, identifier
      "#{write_stamp time}-#{identifier.to_s}"
    end

    def self.from_key_base key_base
      stamp, identifier = key_base.split('-', 2)
      [read_stamp(stamp), identifier]
    end

    def write_key time, identity
      File.join(key_prefix, self.class.to_key_base(time, identity))
    end

    def heartbeat! identity, data
      bucket[write_key now, identity].write data
    end

    def members expiry
      deletes, actives = [], {}
      # The expiry gives an exclusive boundary, not an inclusive,
      # so the minimal allowable key must begin one second after the
      # specified expiry (given a resolution of seconds).
      min_time = Time.now.utc - expiry + 1
      min_key = File.join(key_prefix, min_time.strftime('%Y%m%d%H%M%S-'))
      bucket.with_prefix(key_prefix).each do |obj|
        if obj.key < min_key
          deletes << obj
        else
          o = S3Member.new(obj)
          actives[o.identifier] = o
        end
      end
      deletes! deletes
      actives.values.sort_by {|m| [m.time, m.identifier]}
    end

    def deletes! deletes
      bucket.delete deletes if deletes.size > 0
    end
  end
end

