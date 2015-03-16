module Eventstore
  module Events
    class Write

      attr_accessor :client
      attr_accessor :data
      attr_accessor :id
      attr_accessor :stream_name
      attr_accessor :type

      dependency :logger, Logger

      def self.!(params)
        instance = build(params)
        instance.! do |result|
          yield result
        end
      end

      def self.build(params)
        type = params[:type]
        data = params[:data].to_json
        stream_name = params[:stream_name]

        new(type, data, stream_name, client).tap do |instance|
          Logger.configure instance
          instance.id = java.util.UUID.randomUUID().to_s
        end
      end

      def self.client
        logger = Logger.get self
        @client ||= Vertx::HttpClient.new.tap do |client|
          logger.info "Initializing Client"
          client.port = 2113
          client.host = 'localhost'
        end
      end

      def initialize(type, data, stream_name, client)
        @type = type
        @data = data
        @stream_name = stream_name
        @client = client
      end

      def !
        make_request do |result|
          yield result
        end
      end

      def make_request
        logger.debug "Making request to #{stream_name}"
        request = client.post("/streams/#{stream_name}") do |resp|
          logger.debug "Response #{resp.status_code}"

          if resp.status_code == 201
            yield :success if block_given?
          else
            yield resp.status_code if block_given?
          end
          resp.body_handler do |body|
            # puts "The total body received was #{body.length} bytes"
            # puts body
          end
        end

        request.put_header('ES-EventType', type)
        request.put_header("ES-EventId", id)
        request.put_header('Accept', 'application/vnd.eventstore.atom+json')
        request.put_header('Content-Length', data.length)
        request.put_header('Content-Type', 'application/json')

        request.exception_handler { |e|
          logger.error "Event #{id} failed to write, trying again"
          Vertx.set_timer(rand(1000)) do
            make_request
          end
        }

        request.write_str(data)

        request.end
      end
    end
  end
end