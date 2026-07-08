# The entrypoint the tracer launches under rdbg (`rdbg --open --port N trace_entry.rb`).
# It boots the demo Rails app, then dispatches a single in-process GET "/" — the
# root route — so ArticlesController#index, the Article.published query, and the
# ERB view all execute (and get traced) exactly as they would for a real request.
require_relative "config/boot"

session = ActionDispatch::Integration::Session.new(Rails.application)
session.get "/"

puts "GET / -> HTTP #{session.response.status} (#{session.response.body.bytesize} bytes)"
puts session.response.body
