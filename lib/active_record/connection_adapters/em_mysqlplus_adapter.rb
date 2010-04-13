gem 'activerecord', '>= 2.3.4'

require 'activerecord'
require 'active_record/connection_adapters/mysql_adapter'
require 'em-synchrony'

module ActiveRecord
  module ConnectionAdapters

    class EmMysqlAdapter < MysqlAdapter

      def initialize(connection, logger, host_parameters, connection_parameters, config)
        @hostname = host_parameters[0]
        @port = host_parameters[1]
        @connect_parameters, @config = connection_parameters, config
        super(connection, logger, nil, config)
      end

      def connect
        @connection = EventMachine::Synchrony::ConnectionPool.new(size: @config[:fiber_pool]) do
          EventMachine::MySQL.new({
                                    :host => @hostname,
                                    :port => @port,
                                    :database => @config[:database],
                                    :password => @config[:password],
                                    :socket   => @config[:socket]
          })
        end

        configure_connection
        @connection
      end

    end
  end

  class Base
    def self.em_mysqlplus_connection(config) # :nodoc:
      config = config.symbolize_keys
      host     = config[:host]
      port     = config[:port]
      username = config[:username].to_s if config[:username]
      password = config[:password].to_s if config[:password]

      if config.has_key?(:database)
        database = config[:database]
      else
        raise ArgumentError, "No database specified. Missing argument: database."
      end

      ConnectionAdapters::EmMysqlAdapter.new(nil, logger, [host, port], [database, username, password], config)
    end
  end
end