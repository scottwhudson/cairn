# The compiled Tailwind stylesheet is committed as a static asset
# (app/assets/builds/tailwind.css) and served in production without the
# tailwindcss-rails build tool. This task guards against the committed copy
# drifting from the templates it's generated from: it rebuilds and fails if the
# result differs from what's checked in. Wired into bin/ci and the CI workflow so
# a stale commit can't merge — you never have to remember to rebuild by hand.
#
# Determinism note: the Tailwind CLI version is pinned via tailwindcss-ruby in
# Gemfile.lock, so a rebuild reproduces byte-identical output across machines.
namespace :tailwindcss do
  desc "Rebuild Tailwind and fail if the committed CSS is stale"
  task verify: :environment do
    target = "app/assets/builds/tailwind.css"

    Rake::Task["tailwindcss:build"].invoke

    unless system("git", "diff", "--quiet", "--", target)
      abort <<~MSG.chomp

        #{target} is out of date with the templates it's built from.
        Run `bin/rails tailwindcss:build` and commit the result.
      MSG
    end

    puts "#{target} is up to date."
  end
end
