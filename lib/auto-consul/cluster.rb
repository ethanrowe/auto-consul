require 'uri'

module AutoConsul
  module Cluster
    def self.get_provider_for_uri uri_string
      uri = URI(uri_string)
      Registry.supported_schemes[uri.scheme.downcase].new uri
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
