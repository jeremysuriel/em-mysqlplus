
MAX_RETRIES_ON_DEADLOCKS = 10

class Mysql
  def result
    @cur_result
  end
end

module EventMachine
  class MySQLConnection < EventMachine::Connection

    attr_reader :processing, :connected, :opts
    alias :settings :opts

    DisconnectErrors = [
      'query: not connected',
      'MySQL server has gone away',
      'Lost connection to MySQL server during query'
    ] unless defined? DisconnectErrors

    def initialize(mysql, opts)
      @mysql = mysql
      @fd = mysql.socket
      @opts = opts
      @current = nil
      @queue ||= []
      @processing = false
      @connected = true

      log 'mysql connected'

      self.notify_readable = true
      EM.add_timer(0){ next_query }
    end

    def notify_readable
      log 'readable'
      if item = @current
        @current = nil
        start, response, sql, cblk, eblk, retries = item
        log 'mysql response', Time.now-start, sql
        arg = case response
        when :raw
          result = @mysql.get_result
          @mysql.instance_variable_set('@cur_result', result)
          @mysql
        when :select
          ret = []
          result = @mysql.get_result
          result.each_hash{|h| ret << h }
          log 'mysql result', ret
          ret
        when :update
          result = @mysql.get_result
          @mysql.affected_rows
        when :insert
          result = @mysql.get_result
          @mysql.insert_id
        else
          result = @mysql.get_result
          log 'got a result??', result if result
          nil
        end

        @processing = false
        # result.free if result.is_a? Mysql::Result
        next_query
        cblk.call(arg) if cblk
      else
        log 'readable, but nothing queued?! probably an ERROR state'
        return close
      end
    rescue Mysql::Error => e
      log 'mysql error', e.message
      if e.message =~ /Deadlock/ and retries < MAX_RETRIES_ON_DEADLOCKS
        @queue << [response, sql, cblk, eblk, retries + 1]
        @processing = false
        next_query
      elsif DisconnectErrors.include? e.message
        @queue << [response, sql, cblk, eblk, retries + 1]
        return close
      elsif cb = (eblk || @opts[:on_error])
        cb.call(e)
        @processing = false
        next_query
      else
        raise e
      end
      # ensure
      #   res.free if res.is_a? Mysql::Result
      #   @processing = false
      #   next_query
    end

    def unbind
      log 'mysql disconnect', $!, *($! ? $!.backtrace[0..5] : [])
      @connected = false

      # XXX wait for the next tick until the current fd is removed completely from the reactor
      #
      # XXX in certain cases the new FD# (@mysql.socket) is the same as the old, since FDs are re-used
      # XXX without next_tick in these cases, unbind will get fired on the newly attached signature as well
      #
      # XXX do _NOT_ use EM.next_tick here. if a bunch of sockets disconnect at the same time, we want
      # XXX reconnects to happen after all the unbinds have been processed

      # TODO: reconnect logic will / is broken with new code structure

      EM.add_timer(0) do
        log 'mysql reconnecting'
        @processing = false
        @mysql = EventedMysql._connect @opts
        @fd = @mysql.socket

        @signature = EM.attach_fd @mysql.socket, true
        EM.set_notify_readable @signature, true
        log 'mysql connected'
        EM.instance_variable_get('@conns')[@signature] = self
        @connected = true
        next_query
      end
    end

    def execute(sql, response = nil, cblk = nil, eblk = nil, retries = 0)
      begin
        if not @processing or not @connected
          @processing = true
          @mysql.send_query(sql)
        else
          @queue << [response, sql, cblk, eblk, retries]
          return
        end
      rescue Mysql::Error => e
        log 'mysql error', e.message
        if DisconnectErrors.include? e.message
          @queue << [response, sql, cblk, eblk, retries]
          return close
        else
          raise e
        end
      end

      log 'queuing', response, sql
      @current = [Time.now, response, sql, cblk, eblk, retries]
    end
  
    def close
      @connected = false
      fd = detach
      log 'detached fd', fd
    end

    private

    def next_query
      if @connected and !@processing and pending = @queue.shift
        response, sql, cblk, eblk = pending
        execute(sql, response, cblk, eblk)
      end
    end
  
    def log *args
      return unless @opts[:logging]
      p [Time.now, @fd, (@signature if @signature), *args]
    end

  end
end





class EventedMysql
  def self.execute query, type = nil, cblk = nil, eblk = nil, &blk
    unless nil#connection = connection_pool.find{|c| not c.processing and c.connected }
      @n ||= 0
      connection = connection_pool[@n]
      @n = 0 if (@n+=1) >= connection_pool.size
    end

    connection.execute(query, type, cblk, eblk, &blk)
  end

  def self.reset!
    @connection_pool.each do |c|
      c.close
    end
    @connection_pool = nil
  end
end

