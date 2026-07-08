class Waypoint < ApplicationRecord
  belongs_to :tour

  validates :file, presence: true
  validates :line, presence: true, numericality: { greater_than: 0 }

  before_validation :assign_position, on: :create

  CHANGE_KINDS = %w[added removed modified].freeze

  def absolute_path
    File.expand_path(file, tour.repo_path)
  end

  def location
    "#{file}:#{line}"
  end

  private

  def assign_position
    self.position ||= (tour&.waypoints&.maximum(:position) || -1) + 1
  end
end
