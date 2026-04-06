# Run using bin/ci

CI.run do
  step "Branch check", "bin/check-branch"
  step "Commit message check", "bin/check-commits"

  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --no-pager -i config/brakeman.ignore"

  step "Tests: Rails", "bin/rails db:test:prepare test"
  step "Tests: System", "bin/rails test:system"
end
