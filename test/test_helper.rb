require 'simplecov'
SimpleCov.start 'rails'

ENV["RAILS_ENV"] = "test"

require File.expand_path("../../test/dummy/config/environment.rb",  __FILE__)
require 'rails/test_help'
require 'capybara/rails'
require 'pry'
require 'mocha/setup'
require 'webmock/minitest'
require 'database_cleaner'
require 'capybara/poltergeist'

Rails.backtrace_cleaner.remove_silencers!
ActiveRecord::Migrator.migrations_paths << File.expand_path('../../db/migrate', __FILE__)

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

Minitest.backtrace_filter = Minitest::BacktraceFilter.new

# Transactional fixtures do not work with Selenium tests, because Capybara
# uses a separate server thread, which the transactions would be hidden
# from. We hence use DatabaseCleaner to truncate our test database.
DatabaseCleaner.strategy = :truncation

if ActionDispatch::IntegrationTest.method_defined?(:fixture_path=)
  ActionDispatch::IntegrationTest.fixture_path = File.expand_path("../fixtures", __FILE__)
end

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_path=)
  ActiveSupport::TestCase.fixture_path = File.expand_path("../fixtures", __FILE__)
end

class ActionDispatch::IntegrationTest
  fixtures :all

  # Make the Capybara DSL available in all integration tests
  include Capybara::DSL

  # Stop ActiveRecord from wrapping tests in transactions
  self.use_transactional_fixtures = false

  def setup
    Capybara.register_driver :poltergeist_with_logger do |app|
      Capybara::Poltergeist::Driver.new(app, phantomjs_logger: StringIO.new)
    end

    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
  end

  def login_admin_user
    visit admin_root_path
    fill_in 'Email', with: 'admin@example.com'
    fill_in 'Password', with: 'password'
    click_on 'Login'
    true
  end

  def browser_start
    Capybara.current_driver = :poltergeist_with_logger
    Capybara.default_wait_time = 30
  end

  def browser_end
    Capybara.use_default_driver
  end

  def console_messages
    page.driver.phantomjs_logger.string.split
  end

  def console_message
    self.console_messages.last
  end

  teardown do
    Capybara.reset_sessions!    # Forget the (simulated) browser state
    DatabaseCleaner.clean       # Truncate the database
    Capybara.use_default_driver # Revert Capybara.current_driver to Capybara.default_driver
  end
end

# For functional tests that require authentication
class ActionController::TestCase
  include Devise::TestHelpers
  fixtures :all
end

class ActiveSupport::TestCase
  fixtures :all
end

require 'vcr'
VCR.configure do |c|
  c.cassette_library_dir = 'test/vcr_cassettes'
  c.hook_into :webmock
  c.ignore_localhost = true
end
