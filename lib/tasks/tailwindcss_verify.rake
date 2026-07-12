# The compiled Tailwind stylesheet is committed as a static asset
# (app/assets/builds/tailwind.css) and served in production without the
# tailwindcss-rails build tool. This task guards against that file drifting from
# the sources it's generated from (app/assets/tailwind/application.css plus the
# templates it scans): it rebuilds and fails if the result differs from the copy
# that was already on disk.
#
# The comparison is deliberately against the file's current contents, not against
# git HEAD. Checking out HEAD would flag any uncommitted style work as a failure,
# which would block bin/dev from booting mid-change; what we actually care about
# is whether the build on disk reflects the sources on disk.
#
# Determinism note: the Tailwind CLI version is pinned via tailwindcss-ruby in
# Gemfile.lock, so a rebuild reproduces byte-identical output across machines.
namespace :tailwindcss do
  desc "Rebuild Tailwind and fail if the CSS on disk is stale"
  task verify: :environment do
    target = "app/assets/builds/tailwind.css"

    before = File.binread(target) if File.exist?(target)

    Rake::Task["tailwindcss:build"].invoke

    if before != File.binread(target)
      abort <<~MSG.chomp

        #{target} was out of date with the sources it's built from.
        It has been rebuilt in place — review and commit the result.
      MSG
    end

    puts "#{target} is up to date."
  end
end
