require "influxdb/rails/middleware/subscriber"

module InfluxDB
  module Rails
    module Middleware
      class RequestSubscriber < Subscriber
        def call(_name, start, finish, _id, payload)
          return unless enabled?

          ts = InfluxDB.convert_timestamp(finish.utc, configuration.time_precision)
          begin
            series(payload, start, finish).each do |series_name, value|
              InfluxDB::Rails.client.write_point series_name, values: { value: value }, tags: tags(payload), timestamp: ts
            end
          rescue StandardError => e
            log :error, "[InfluxDB::Rails] Unable to write points: #{e.message}"
          ensure
            Thread.current[:_influxdb_rails_controller] = nil
            Thread.current[:_influxdb_rails_action]     = nil
          end
        end

        private

        def series(payload, start, finish)
          {
            configuration.series_name_for_controller_runtimes => ((finish - start) * 1000).ceil,
            configuration.series_name_for_view_runtimes       => (payload[:view_runtime] || 0).ceil,
            configuration.series_name_for_db_runtimes         => (payload[:db_runtime] || 0).ceil,
          }
        end

        def tags(payload)
          configuration.tags_middleware.call(
            {
              method:      "#{payload[:controller]}##{payload[:action]}",
              status:      payload[:status],
              format:      payload[:format],
              http_method: payload[:method],
              server:      Socket.gethostname,
              app_name:    configuration.application_name,
            }.reject { |_, value| value.nil? })
        end
      end
    end
  end
end
