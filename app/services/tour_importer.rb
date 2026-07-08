require "yaml"

# Imports an author-authored tour file shipped alongside the code under review
# into a Tour's waypoints. The file (conventionally `tour.yml` at the repo root)
# is how a PR author ships the "here's what to look at" narrative with their diff.
#
# Expected shape:
#   title: Optional tour title
#   description: Optional prose
#   waypoints:
#     - file: script/sample_app/pricing.rb
#       line: 24
#       note: Why this changed...
#       change_kind: modified      # added | removed | modified
#       condition: qty > 10        # optional DAP conditional breakpoint
class TourImporter
  class Error < StandardError; end

  FILENAMES = %w[tour.yml tour.yaml .tour.yml].freeze

  def initialize(tour)
    @tour = tour
  end

  # Returns the number of waypoints imported. With replace:true, existing
  # author-authored waypoints are cleared first (reviewer bookmarks are kept).
  def import(replace: false)
    data = load_file
    entries = Array(data["waypoints"])
    raise Error, "Tour file has no waypoints" if entries.empty?

    @tour.transaction do
      apply_metadata(data)
      @tour.waypoints.where(author: "author").destroy_all if replace
      entries.each_with_index { |entry, i| build_waypoint(entry, i) }
      @tour.save!
    end
    entries.size
  end

  def tour_file_path
    FILENAMES.map { |name| File.join(@tour.repo_path, name) }.find { |p| File.file?(p) }
  end

  private

  def load_file
    path = tour_file_path
    raise Error, "No tour file (#{FILENAMES.join(', ')}) found in #{@tour.repo_path}" unless path
    YAML.safe_load_file(path) || {}
  rescue Psych::SyntaxError => e
    raise Error, "Tour file is not valid YAML: #{e.message}"
  end

  def apply_metadata(data)
    @tour.title = data["title"] if data["title"].present? && @tour.title.blank?
    @tour.description = data["description"] if data["description"].present? && @tour.description.blank?
  end

  def build_waypoint(entry, position)
    @tour.waypoints.build(
      file: entry.fetch("file"),
      line: Integer(entry.fetch("line")),
      note: entry["note"],
      condition: entry["condition"],
      change_kind: entry["change_kind"],
      author: "author",
      position: position
    )
  rescue KeyError => e
    raise Error, "Waypoint ##{position + 1} is missing #{e.message}"
  end
end
