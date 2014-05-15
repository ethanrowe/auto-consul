require 'uri'

module AutoConsul
  class Cluster
    def self.get_provider_for_uri uri_string
      uri = URI(uri_string)
      Registry.supported_schemes[uri.scheme.downcase].new uri
    end

    attr_reader :uri_string

    def initialize uri
      @uri_string = uri
    end

    def servers
      @servers ||= self.class.get_provider_for_uri File.join(uri_string, 'servers')
    end

    def agents
      @agents ||= self.class.get_provider_for_uri File.join(uri_string, 'agents')
    end

    def set_mode! local_state, expiry, desired_servers=1
      if servers.members(expiry).size < desired_servers
        local_state.set_server!
      else
        local_state.set_agent!
      end
    end

    module Registry
      def self.supported_schemes
        constants.inject({}) do |a, const|
          if const.to_s =~ /^(.+?)Provider$/
            a[$1.downcase] = const_get(const)
          end
          a
        end
      end

      class Provider
        attr_reader :uri

        def initialize uri
          @uri = uri
        end
      end
    end
  end
end

require_relative 'providers/s3'
