module Debug
  # Process-global home for the one live DapClient connection.
  #
  # Debug::Session attaches a client to a running rdbg DAP server and parks it
  # here; the reader/dispatcher threads it owns keep running after the request
  # returns. Later step actions look the client back up to drive it. This
  # is a single-process POC convenience (dev's async ActionCable adapter shares
  # the web process, so the client's broadcasts reach the browser).
  module SessionRegistry
    @client = nil
    @lock = Mutex.new

    class << self
      def put(client)
        @lock.synchronize { @client = client }
      end

      def get
        @lock.synchronize { @client }
      end

      def clear
        @lock.synchronize { @client = nil }
      end

      def active?
        !get.nil?
      end
    end
  end
end
