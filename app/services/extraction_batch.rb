# Runs DocumentExtraction over a set of documents concurrently.
#
# Each worker thread pulls the next document off a shared queue, so slow
# documents don't stall the batch. Requires a DB connection pool larger than
# the thread count (see config/database.yml) since each worker holds a
# connection while its API call is in flight.
class ExtractionBatch
  THREADS = 64

  def self.call(scope, threads: THREADS)
    documents = scope.to_a
    queue = Queue.new
    documents.each { |document| queue << document }

    Array.new([threads, documents.size].min) do
      Thread.new do
        while (document = (queue.pop(true) rescue nil))
          ActiveRecord::Base.connection_pool.with_connection do
            DocumentExtraction.new(document).call
          end
        end
      end
    end.each(&:join)

    documents.each(&:reload)
  end
end
