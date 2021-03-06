# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run the gemspec command
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{em-mysqlplus}
  s.version = "0.1.3"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Ilya Grigorik", "Aman Gupta"]
  s.date = %q{2010-06-19}
  s.description = %q{Async MySQL driver for Ruby/Eventmachine}
  s.email = %q{ilya@igvita.com}
  s.extra_rdoc_files = [
    "README.md"
  ]
  s.files = [
    "README.md",
     "Rakefile",
     "VERSION",
     "lib/active_record/connection_adapters/em_mysqlplus_adapter.rb",
     "lib/active_record/patches.rb",
     "lib/em-activerecord.rb",
     "lib/em-mysqlplus.rb",
     "lib/em-mysqlplus/connection.rb",
     "lib/em-mysqlplus/mysql.rb",
     "spec/activerecord_spec.rb",
     "spec/database.yml",
     "spec/helper.rb",
     "spec/mysql_spec.rb"
  ]
  s.homepage = %q{http://github.com/igrigorik/em-mysql}
  s.rdoc_options = ["--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{em-mysqlplus}
  s.rubygems_version = %q{1.3.6}
  s.summary = %q{Async MySQL driver for Ruby/Eventmachine}
  s.test_files = [
    "spec/activerecord_spec.rb",
     "spec/helper.rb",
     "spec/mysql_spec.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<eventmachine>, [">= 0.12.9"])
    else
      s.add_dependency(%q<eventmachine>, [">= 0.12.9"])
    end
  else
    s.add_dependency(%q<eventmachine>, [">= 0.12.9"])
  end
end

