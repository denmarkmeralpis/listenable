# frozen_string_literal: true

require_relative "lib/listenable/version"

Gem::Specification.new do |spec|
  spec.name = "listenable"
  spec.version = Listenable::VERSION
  spec.authors = ["Den Meralpis"]
  spec.email = ["denmarkmeralpis@gmail.com"]

  spec.summary       = "A Rails DSL for model event listeners using ActiveSupport::Notifications."
  spec.description   = "Listenable makes it easy to wire ActiveRecord models to listener classes. " \
                      "Define <Model>Listener classes in app/listeners, declare listen :on_created, " \
                      ":on_updated, etc., and Listenable automatically injects callbacks and subscribes " \
                      "to ActiveSupport::Notifications."
  spec.homepage      = "https://github.com/denmarkmeralpis/listenable"

  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/denmarkmeralpis/listenable"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.add_dependency "activesupport", ">= 6.0"
end
