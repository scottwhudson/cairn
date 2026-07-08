class TraceRun < ApplicationRecord
  belongs_to :tour, optional: true

  validates :label, presence: true

  before_save :sync_event_count

  # Ingest a JSONL trace (as produced by TraceRecorder) into the events column.
  def self.from_jsonl(jsonl, **attrs)
    events = jsonl.each_line.filter_map do |line|
      line = line.strip
      JSON.parse(line) unless line.empty?
    end
    new(attrs.merge(events: events))
  end

  private

  def sync_event_count
    self.event_count = events.is_a?(Array) ? events.size : 0
  end
end
