require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    gemspec.name = "em-mysql"
    gemspec.summary = "Async MySQL driver for Ruby/Eventmachine"
    gemspec.description = gemspec.summary
    gemspec.email = "ilya@igvita.com"
    gemspec.homepage = "http://github.com/igrigorik/em-mysql"
    gemspec.authors = ["Ilya Grigorik", "Aman Gupta"]
    gemspec.add_dependency('eventmachine', '>= 0.12.9')
    gemspec.rubyforge_project = "em-mysql"
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end
