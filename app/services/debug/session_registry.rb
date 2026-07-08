module Debug
  # Process-global home for live DapClient connections, keyed by tour id.
  #
  # A DebugSessionJob attaches a client and parks it here; the reader/dispatcher
  # threads it owns keep running after the job returns. Controller step actions
  # look the client back up to drive execution. This is a single-process POC
  # convenience (dev runs jobs in-process with the async ActiveJob adapter) —
  # a multi-process deployment would move this to an out-of-band supervisor.
  module SessionRegistry
    @clients = {}
    @lock = Mutex.new

    class << self
      def put(tour_id, client)
        @lock.synchronize { @clients[tour_id.to_i] = client }
      end

      def get(tour_id)
        @lock.synchronize { @clients[tour_id.to_i] }
      end

      def delete(tour_id)
        @lock.synchronize { @clients.delete(tour_id.to_i) }
      end

      def active?(tour_id)
        !get(tour_id).nil?
      end
    end
  end
end
