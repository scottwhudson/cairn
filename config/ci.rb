# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Assets: Tailwind fresh", "bin/rails tailwindcss:verify"

  step "Style: Ruby", "bin/standardrb"
  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Tests: Rails", "bin/rails test"
end
