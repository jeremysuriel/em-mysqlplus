require "eventmachine"
require "mysqlplus"
require "fcntl"

module EventMachine
  class MySQL

    self::Mysql = ::Mysql unless defined? self::Mysql

    attr_reader :connection

    def initialize(opts)
      unless EM.respond_to?(:watch) and Mysql.method_defined?(:socket)
        raise RuntimeError, 'mysqlplus and EM.watch are required for EventedMysql'
      end

      @settings = { :debug => false }.merge!(opts)
      @connection = connect(@settings)
    end

    def close
      @connection.close
    end

    def query(sql, &blk)
      df = EventMachine::DefaultDeferrable.new
      cb = blk || Proc.new { |r| df.succeed(r) }
      eb = Proc.new { |r| df.fail(r) }

      @connection.execute(sql, cb, eb)

      df
    end
    alias :real_query :query

    # behave as a normal mysql connection 
    def method_missing(method, *args, &block)
      if @connection.respond_to? method
        @connection.send(method, args)
      end
    end

    def connect(opts)
      if conn = connect_socket(opts)
        debug [:connect, conn.socket, opts]
        EM.watch(conn.socket, EventMachine::MySQLConnection, conn, opts, self)
      else
        # invokes :errback callback in opts before firing again
        debug [:reconnect]
        EM.add_timer(5) { connect opts }
      end
    end

    # stolen from sequel
    def connect_socket(opts)
      conn = Mysql.init

      # set encoding _before_ connecting
      if charset = opts[:charset] || opts[:encoding]
        conn.options(Mysql::SET_CHARSET_NAME, charset)
      end

      conn.options(Mysql::OPT_LOCAL_INFILE, 'client')
      conn.real_connect(
        opts[:host] || 'localhost',
        opts[:user] || 'root',
        opts[:password],
        opts[:database],
        opts[:port],
        opts[:socket],
        0 +
          # XXX multi results require multiple callbacks to parse
        # Mysql::CLIENT_MULTI_RESULTS +
        # Mysql::CLIENT_MULTI_STATEMENTS +
        (opts[:compress] == false ? 0 : Mysql::CLIENT_COMPRESS)
      )

      # increase timeout so mysql server doesn't disconnect us
      # this is especially bad if we're disconnected while EM.attach is
      # still in progress, because by the time it gets to EM, the FD is
      # no longer valid, and it throws a c++ 'bad file descriptor' error
      # (do not use a timeout of -1 for unlimited, it does not work on mysqld > 5.0.60)
      conn.query("set @@wait_timeout = #{opts[:timeout] || 2592000}")

      # we handle reconnecting (and reattaching the new fd to EM)
      conn.reconnect = false

      # By default, MySQL 'where id is null' selects the last inserted id
      # Turn this off. http://dev.rubyonrails.org/ticket/6778
      conn.query("set SQL_AUTO_IS_NULL=0")

      # get results for queries
      conn.query_with_result = true

      conn
    rescue Mysql::Error => e
      if cb = opts[:errback]
        cb.call(e)
        nil
      else
        raise e
      end
    end

    def debug(data)
      p data if @settings[:debug]
    end
  end
end
