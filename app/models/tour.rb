class Tour < ApplicationRecord
  has_many :waypoints, -> { order(:position) }, dependent: :destroy
  has_many :trace_runs, dependent: :nullify

  accepts_nested_attributes_for :waypoints, allow_destroy: true

  validates :title, :repo_path, :entrypoint, presence: true

  STATUSES = %w[idle starting running stopped errored].freeze

  # Absolute path to the debuggee entrypoint that a session will launch under rdbg.
  def entrypoint_path
    File.expand_path(entrypoint, repo_path)
  end

  # Breakpoints handed to the DAP client, derived from the tour's waypoints
  # (i.e. the changed regions), keyed by absolute source path.
  def breakpoints_by_file
    waypoints.group_by { |w| File.expand_path(w.file, repo_path) }.transform_values do |wps|
      wps.map { |w| { line: w.line, condition: w.condition.presence, waypoint_id: w.id } }
    end
  end

  def update_status!(new_status)
    update!(status: new_status) if STATUSES.include?(new_status)
  end
end
