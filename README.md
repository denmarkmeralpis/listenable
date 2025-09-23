# Listenable

Listenable is a Rails DSL that connects your ActiveRecord models to dedicated listener classes using `ActiveSupport::Notifications`.

Instead of cluttering your models with callbacks, you declare listeners in `app/listeners`. Listenable automatically wires up the callbacks, instruments events, and runs your listener methods. It supports both synchronous (blocking) and asynchronous (non-blocking) execution modes.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add listenable
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install listenable
```

**Note**: For asynchronous listener support, make sure you have the `concurrent-ruby` gem installed (usually included with Rails by default).

## Usage

#### 1. Define a model
```ruby
# app/models/user.rb
class User < ApplicationRecord
end
```

#### 2. Create a listener
```ruby
# app/listeners/user_listener.rb
class UserListener
  include Listenable

  listen :on_created, :on_updated, :on_deleted

  # Handle user creation
  def self.on_created(record)
    Rails.logger.info "User created: #{user.id}"
    SendWelcomeEmailJob.perform_later(user)
  end

  # Handle user update
  def self.on_updated(record)
    Rails.logger.info "User updated: #{user.id}"
    SendProfileUpdateNotificationJob.perform_later(user)
  end

  # Handle user deletion
  def self.on_deleted(record)
    Rails.logger.info "User deleted: #{user.id}"
    ArchiveUserDataJob.perform_later(user)
  end
end
```

#### 3. Done
* When a user is created, `UserListener.on_created` runs.
* When a user is updated, `UserListener.on_updated` runs.
* When a user is deleted, `UserListener.on_deleted` runs.

Under the hood:
* `after_create`, `after_update`, and `after_destroy` callbacks are injected into the model.
* `ActiveSupport::Notifications.instrument` fires events like `user.created`.
* The Railtie subscribes your listener methods to those events.

## Synchronous vs Asynchronous Execution

Listenable supports both synchronous (blocking) and asynchronous (non-blocking) listener execution:

### Synchronous Listeners (Default)
By default, listeners execute synchronously in the same thread as your model operations:

```ruby
class UserListener
  include Listenable

  # Synchronous execution (default)
  listen :on_created, :on_updated, :on_deleted

  def self.on_created(user)
    Rails.logger.info "User created: #{user.id}"
    # This runs in the same request thread
  end
end
```

### Asynchronous Listeners
For non-blocking execution, use the `async: true` option:

```ruby
class UserListener
  include Listenable

  # Asynchronous execution - runs in background thread
  listen :on_created, :on_updated, :on_deleted, async: true

  def self.on_created(user)
    Rails.logger.info "User created: #{user.id}"
    # This runs in a separate thread, doesn't block the request
    SendWelcomeEmailService.call(user)  # Safe for heavier operations
  end
end
```

### Mixed Execution Modes
You can mix synchronous and asynchronous listeners by calling `listen` multiple times:

```ruby
class UserListener
  include Listenable

  # Some listeners run synchronously
  listen :on_created

  # Others run asynchronously
  listen :on_updated, :on_deleted, async: true

  def self.on_created(user)
    # Runs synchronously - blocks request
    user.update!(status: 'active')
  end

  def self.on_updated(user)
    # Runs asynchronously - doesn't block request
    UserAnalyticsService.new(user).calculate_metrics
  end

  def self.on_deleted(user)
    # Also runs asynchronously
    CleanupUserDataService.call(user)
  end
end
```

## ⚠️ Important: Execution Modes and Performance

### Synchronous Listeners (Default Behavior)

**Synchronous listeners execute in the same thread and will block the current request.** This means that all synchronous listener methods run in the same request/transaction as your model operations, which can impact performance and response times.

**For synchronous listeners**: Always queue heavy operations in background jobs to maintain application performance:

```ruby
class UserListener
  include Listenable

  # Synchronous listeners (default)
  listen :on_created, :on_updated

  def self.on_created(user)
    # ✅ Good - Lightweight operations or queue background jobs
    SendWelcomeEmailJob.perform_later(user)
    NotifyAdminsJob.perform_later(user)
  end

  def self.on_updated(user)
    # ❌ Avoid - Heavy synchronous operations that block requests
    # UserAnalyticsService.new(user).calculate_metrics  # This blocks!

    # ✅ Better - Queue in background
    CalculateUserMetricsJob.perform_later(user)
  end
end
```

### Asynchronous Listeners (Non-blocking)

**Asynchronous listeners execute in separate threads and don't block requests.** This allows for heavier operations without impacting response times:

```ruby
class UserListener
  include Listenable

  # Asynchronous listeners - safe for heavier operations
  listen :on_created, :on_updated, async: true

  def self.on_created(user)
    # ✅ Safe - Runs in background thread
    UserAnalyticsService.new(user).calculate_metrics
    SendWelcomeEmailService.call(user)
  end

  def self.on_updated(user)
    # ✅ Safe - Heavy operations won't block requests
    ExternalApiService.notify_user_update(user)
    GenerateUserReportService.call(user)
  end
end
```

**Note**: Asynchronous listeners use `Concurrent::Promises` for thread-safe execution. Errors in async listeners are logged but won't affect the main request flow.

### Choosing the Right Mode

- **Use synchronous listeners** for:
  - Critical operations that must complete before the request finishes
  - Simple, fast operations (logging, simple updates)
  - Operations that need to participate in the same database transaction

- **Use asynchronous listeners** for:
  - Heavy computations or external API calls
  - Non-critical operations that can fail independently
  - Operations that don't need to complete before the response is sent

## Supported hooks
| Listener hook         | Model callback        | Execution Mode |
|-----------------------|-----------------------|----------------|
| `on_created`          | `after_create`       | Synchronous (default) or Asynchronous with `async: true` |
| `on_updated`          | `after_update`       | Synchronous (default) or Asynchronous with `async: true` |
| `on_deleted`          | `after_destroy`      | Synchronous (default) or Asynchronous with `async: true` |

All hooks support both synchronous and asynchronous execution modes via the `async: true` option.

## Runtime Toggle
By default, listeners are always active in development and production.

You can enable/disable them dynamically at runtime using:

```ruby
Listenable.enabled = false  # disable all listeners
Listenable.enabled = true   # re-enable listeners
```

This does not require restarting your Rails server or test suite.

## RSpec/Test Integration
You usually don’t want listeners firing in tests (e.g. sending jobs or emails).

Disable them globally in your test suite:

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.before(:suite) do
    Listenable.enabled = false
  end

  # Enable listeners selectively
  config.around(:each, listenable: true) do |example|
    prev = Listenable.enabled
    Listenable.enabled = true
    example.run
    Listenable.enabled = prev
  end
end
```

Now:

```ruby
RSpec.describe User do
  it 'does not fire listeners by default' do
    expect(UserListener).not_to receive(:on_created)
    User.create!(name: 'Pedro')
  end

  it 'fires synchronous listeners when enabled', listenable: true do
    expect(UserListener).to receive(:on_created)
    User.create!(name: 'Pedro')
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Todo:
* Create rake tasks to generate listener files.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/denmarkmeralpis/listenable. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/denmarkmeralpis/listenable/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Listenable project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/denmarkmeralpis/listenable/blob/main/CODE_OF_CONDUCT.md).
