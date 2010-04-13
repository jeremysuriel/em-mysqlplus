require 'helper'
require 'logger'
require 'yaml'
require 'erb'

require 'lib/em-activerecord'

RAILS_ENV='test'

ActiveRecord::Base.configurations = YAML::load(ERB.new(File.read(File.join(File.dirname(__FILE__), 'database.yml'))).result)
ActiveRecord::Base.default_timezone = :utc
ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = Logger::INFO
ActiveRecord::Base.pluralize_table_names = false
ActiveRecord::Base.time_zone_aware_attributes = true
Time.zone = 'UTC'

describe "ActiveRecord Driver for EM-MySQLPlus" do
  it "should establish AR connection" do
    EventMachine.run {
      Fiber.new {
        ActiveRecord::Base.establish_connection
        result = ActiveRecord::Base.connection.query('select sleep(1)')
        p result

        EventMachine.stop
      }.resume
    }
  end

  it "should use fiber aware ConnectionPool" do
    EventMachine.run {
      results = []

      3.times do |n|
        Fiber.new {
          ActiveRecord::Base.establish_connection
          results.push ActiveRecord::Base.connection.query('select sleep(1)')
        }.resume
      end

      EM.add_timer(1.5) {
        results.size.should == 3
        EventMachine.stop
      }
    }
  end

end
