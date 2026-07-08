require "open3"

namespace :trace do
  desc "Record before/after execution traces of the sample app into TraceRuns"
  task record: :environment do
    sample_dir = Rails.root.join("script", "sample_app")
    tour = Tour.find_by(entrypoint: "run.rb")

    {
      "before" => "pricing_before.rb",
      "after"  => "pricing.rb"
    }.each do |label, impl|
      jsonl, status = Open3.capture2(
        "ruby", sample_dir.join("trace_entry.rb").to_s, impl, chdir: sample_dir.to_s
      )
      raise "trace_entry failed for #{impl}" unless status.success?

      run = TraceRun.from_jsonl(jsonl, tour: tour, label: label,
                                       entrypoint: impl, git_ref: (label == "after" ? "fix/inclusive-tiers" : "main"))
      run.save!
      puts "Recorded '#{label}' trace: TraceRun ##{run.id} (#{run.event_count} events)"
    end

    puts "Diff them at /trace_diffs/<before_id>/<after_id>"
  end
end
