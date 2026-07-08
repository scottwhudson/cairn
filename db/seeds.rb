# Seed a ready-to-run tour against the bundled sample app.
sample_repo = Rails.root.join("script", "sample_app").to_s

tour = Tour.find_or_initialize_by(entrypoint: "run.rb", repo_path: sample_repo)
tour.assign_attributes(
  title: "Fix: inclusive volume-discount tiers",
  description: "Boundary orders (qty == 10 / 100) were missing their discount. Step through the fix.",
  git_ref: "fix/inclusive-tiers"
)
tour.save!

# Pull waypoints from the shipped tour.yml (idempotent: replace author-authored ones).
imported = TourImporter.new(tour).import(replace: true)

puts "Seeded tour ##{tour.id} '#{tour.title}' with #{imported} waypoint(s)."

# Record before/after execution traces for the trace-diff demo (idempotent).
if tour.trace_runs.none?
  require "open3"
  { "before" => "pricing_before.rb", "after" => "pricing.rb" }.each do |label, impl|
    jsonl, status = Open3.capture2("ruby", "trace_entry.rb", impl, chdir: sample_repo)
    next unless status.success?
    TraceRun.from_jsonl(jsonl, tour: tour, label: label, entrypoint: impl,
                        git_ref: (label == "after" ? "fix/inclusive-tiers" : "main")).save!
  end
  puts "Recorded #{tour.trace_runs.count} execution traces."
end

before_run, after_run = tour.trace_runs.order(:id).last(2)
puts "Open tour:  http://localhost:3000/tours/#{tour.id}"
puts "Trace diff: http://localhost:3000/trace_diffs/#{before_run&.id}/#{after_run&.id}"

# --- Demo: trace a real Rails app's root route ------------------------------
# script/demo_blog is a small, real Rails 8 app. Its trace_entry.rb boots the
# app and dispatches an in-process GET "/", so the tracer captures the whole
# router -> ArticlesController#index -> Article.published -> view render stack.
blog_repo = Rails.root.join("script", "demo_blog").to_s

blog_tour = Tour.find_or_initialize_by(entrypoint: "trace_entry.rb", repo_path: blog_repo)
blog_tour.assign_attributes(
  title: "Demo blog: root route",
  description: "Step through GET \"/\" of a real Rails app: load published articles from Postgres and render them.",
  git_ref: "main"
)
blog_tour.save!
blog_imported = TourImporter.new(blog_tour).import(replace: true)

puts "Seeded tour ##{blog_tour.id} '#{blog_tour.title}' with #{blog_imported} waypoint(s)."
puts "Open blog tour: http://localhost:3000/tours/#{blog_tour.id}"
