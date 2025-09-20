# Listenable

Listenable is a Rails DSL that connects your ActiveRecord models to dedicated listener classes using `ActiveSupport::Notifications`.

Instead of cluttering your models with callbacks, you declare listeners in `app/listeners`. Listenable automatically wires up the callbacks, instruments events, and runs your listener methods.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add listenable
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install listenable
```

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

## Supported hooks
| Listener hook         | Model callback        |
|-----------------------|-----------------------|
| `on_created`          | `after_create`       |
| `on_updated`          | `after_update`       |
| `on_deleted`          | `after_destroy`      |

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

  it 'fires listeners when enabled', listenable: true do
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
* RSpec tests for Railtie and integration tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/denmarkmeralpis/listenable. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/denmarkmeralpis/listenable/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Listenable project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/denmarkmeralpis/listenable/blob/main/CODE_OF_CONDUCT.md).
