# Copilot Instructions for Mum

## Project Overview
This is a Rails 8.1.2 application configured without Active Record (database-less). The application uses modern Rails conventions and the Hotwire stack.

## Technology Stack
- Ruby 3.4.4
- Rails 8.1.2
- Hotwire (Turbo + Stimulus)
- Importmap for JavaScript
- Propshaft for asset pipeline
- Puma web server

## Code Style and Quality
- Follow RuboCop Rails Omakase styling conventions
- Lint code with: `bin/rubocop`
- Run security scans with: `bin/brakeman`
- Audit JavaScript dependencies with: `bin/importmap audit`

## Testing
- Use Rails' built-in test framework (Test::Unit)
- Run unit tests: `bin/rails test`
- Run system tests: `bin/rails test:system`
- Run all tests: `bin/rails test test:system`
- System tests use Capybara with Selenium WebDriver

## Key Conventions
- This app does NOT use Active Record - avoid database-related code
- Use Turbo for dynamic updates instead of heavy JavaScript
- Prefer Stimulus controllers for JavaScript behavior
- Follow Rails 8 conventions and modern patterns

## Development Commands
- Start server: `bin/rails server`
- Run console: `bin/rails console`
- Run linter: `bin/rubocop`
- Run security scan: `bin/brakeman`
