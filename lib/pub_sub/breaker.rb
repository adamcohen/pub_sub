require 'thread'

module PubSub
  class Breaker
    NUM_ERRORS_THRESHOLD = 10
    REENABLE_AFTER = 60 # seconds
    ERROR_WINDOW = 60 # seconds
    @@semaphore = Mutex.new

    class << self

      def execute(&block)
        begin
          get_breaker.run do
            block.call
          end
        rescue CB2::BreakerOpen => e
          PubSub.report_error e
          on_breaker_open
        rescue Exception => e
          # Intercept for breaker's tracking purposes
          PubSub.report_error e
          raise # will be caught by the breaker once enough of these accumulate
        end
      end


    protected

      # Override to return the desired instance
      def get_breaker
        region = PubSub.config.current_region
        @@semaphore.synchronize do
          @@current_breaker ||= new_breaker(region)
        end
      end

      # Override to provide alternative implementation.
      def on_breaker_open
        PubSub.logger.info "#{@@current_breaker} detected more than #{NUM_ERRORS_THRESHOLD} errors"\
         "during last #{ERROR_WINDOW} seconds. Will pause execution for #{REENABLE_AFTER} seconds"
      end

      def new_breaker(region)
        CB2::Breaker.new(
          service: "aws-#{region}-breaker",
          duration: ERROR_WINDOW,
          threshold: NUM_ERRORS_THRESHOLD,
          reenable_after: REENABLE_AFTER,
          redis: Redis.current)
      end

    end
  end
end
