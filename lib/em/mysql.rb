require 'rubygems'
require 'eventmachine'
require 'mysqlplus'

class EventedMysql < EM::Connection
  def initialize mysql, opts
    @mysql = mysql
    @opts = opts
    @queue = []
    @pending = []
    @processing = false
  end
  attr_reader :processing

  def connection_completed
    next_query
  end

  def notify_readable
    if item = @queue.shift
      start, response, query, blk = item
      # p [@mysql.socket, query, 'took', Time.now-start, 'seconds']
      res = case response
            when :select
              @mysql.get_result
              ret = []
              @mysql.use_result.each_hash{|h| ret << h }
              ret
            when :update
              @mysql.get_result
              @mysql.affected_rows
            when :insert
              @mysql.get_result
              @mysql.insert_id
            else
              @mysql.get_result
              @mysql.use_result rescue nil
            end

      blk.call res if blk
    end
  ensure
    res.free if res.is_a? Mysql::Result
    @processing = false
    next_query
  end

  def unbind
    cp = EventedMysql.instance_variable_get('@connection_pool') and cp.delete(self)

    # XXX wait for the next tick, so the FD is removed completely from the reactor
    # XXX in certain cases the new FD# (@mysql.socket) is the same as the old, since FDs are re-used
    # XXX without next_tick in these cases, unbind will get fired on the newly attached signature as well
    EM.next_tick do
      @processing = false
      @mysql = EventedMysql._connect @opts
      @signature = EM.attach_file @mysql.socket, EM::AttachInNotifyReadableMode, EM::AttachInWriteMode
      EM.instance_variable_get('@conns')[@signature] = self
    end unless $! # no reconnect if ruby process is exiting.
  end

  DisconnectErrors = [
    'query: not connected',
    'MySQL server has gone away'
  ] unless defined? DisconnectErrors

  def execute sql, response = nil, &blk
    begin
      unless @processing
        @processing = true
        @mysql.send_query(sql)
        # p [@mysql.socket, :sent, sql]
      else
        @pending << [response, sql, blk]
        return
      end
    rescue Mysql::Error => e
      if DisconnectErrors.include? e.message
        @pending << [response, sql, blk]
        close_connection
        return
      else
        raise e
      end
    end

    @queue << [Time.now, response, sql, blk]
  end
  
  def close
    @mysql.close
    close_connection
  end

  private
  
  def next_query
    if !@processing and pending = @pending.shift
      response, sql, blk = pending
      execute(sql, response, &blk)
    end
  end

  public

  def self.connect opts
    unless EM.respond_to?(:attach) and Mysql.method_defined?(:socket)
      raise RuntimeError, 'mysqlplus and EM.attach are required for EventedMysql'
    end

    conn = _connect(opts)

    # XXX EM.attach should take fd directly
    EM.attach IO.new(conn.socket), self, conn, opts
  end

  self::Mysql = ::Mysql unless defined? self::Mysql

  # stolen from sequel
  def self._connect opts
    conn = Mysql.init
    conn.options(Mysql::OPT_LOCAL_INFILE, 'client')
    conn.real_connect(
      opts[:host] || 'localhost',
      opts[:user] || 'root',
      opts[:password],
      opts[:database],
      opts[:port],
      opts[:socket],
      Mysql::CLIENT_MULTI_RESULTS +
      Mysql::CLIENT_MULTI_STATEMENTS +
      Mysql::CLIENT_COMPRESS
    )

    conn.query_with_result = false
    if encoding = opts[:encoding] || opts[:charset]
      conn.query("set character_set_connection = '#{encoding}'")
      conn.query("set character_set_client = '#{encoding}'")
      conn.query("set character_set_database = '#{encoding}'")
      conn.query("set character_set_server = '#{encoding}'")
      conn.query("set character_set_results = '#{encoding}'")
    end

    # we handle reconnecting (and reattaching the new fd to EM)
    conn.reconnect = false
    conn
  end
end

class EventedMysql
  def self.settings
    @settings ||= { :connections => 4 }
  end

  def self.execute query, type = nil, &blk
    unless connection = connection_pool.find{|c| not c.processing }
      @n ||= 0
      connection = connection_pool[@n]
      @n = 0 if (@n+=1) >= connection_pool.size
    end

    connection.execute(query, type, &blk)
  end

  %w[ select insert update ].each do |type| class_eval %[

    def self.#{type} query, &blk
      execute query, :#{type}, &blk
    end

  ] end

  def self.all query, type = nil, &blk
    responses = 0
    connection_pool.each do |c|
      c.execute(query, type) do
        responses += 1
        blk.call if blk and responses == @connection_pool.size
      end
    end
  end

  def self.connection_pool
    @connection_pool ||= (1..settings[:connections]).map{ EventedMysql.connect(settings) }
    (1..(settings[:connections]-@connection_pool.size)).each do
      @connection_pool << EventedMysql.connect(settings)
    end unless settings[:connections] == @connection_pool.size
    @connection_pool
  end
end

if __FILE__ == $0 and require 'em/spec'

  EM.describe EventedMysql, 'individual connections' do

    should 'create a new connection' do
      @mysql = EventedMysql.connect :host => '127.0.0.1',
                                    :port => 3306,
                                    :database => 'test'

      @mysql.class.should == EventedMysql
      done
    end
      
    should 'execute sql' do
      start = Time.now

      @mysql.execute('select sleep(0.2)'){
        (Time.now-start).should.be.close 0.2, 0.1
        done
      }
    end
  
    should 'run select queries and return results' do
      @mysql.execute('select 1+2', :select){ |res|
        res.size.should == 1
        res.first['1+2'].should == '3'
        done
      }
    end
  
  end

  EM.describe EventedMysql, 'connection pools' do

    should 'run queries in parallel' do
      n = 0
      EventedMysql.select('select sleep(0.25)'){ n+=1 }
      EventedMysql.select('select sleep(0.25)'){ n+=1 }
      EventedMysql.select('select sleep(0.25)'){ n+=1 }

      EM.add_timer(0.30){
        n.should == 3
        done
      }
    end

  end

  SQL = EventedMysql
  def SQL(query, &blk) SQL.select(query, &blk) end

  EM.describe SQL, 'sql api' do
    
    should 'insert and select rows' do
      SQL.all('use test')

      SQL.execute('drop table if exists evented_mysql_test'){
        :table_dropped.should == :table_dropped
        SQL.execute('create table evented_mysql_test (id int primary key auto_increment, num int not null)'){
          :table_created.should == :table_created
          SQL.insert('insert into evented_mysql_test (num) values (10)'){ |id|
            id.should == 1
            SQL('select * from evented_mysql_test'){ |res|
              res.first.should == { 'id' => '1', 'num' => '10' }
              done
            }
          }
        }
      }
    end

  end

end