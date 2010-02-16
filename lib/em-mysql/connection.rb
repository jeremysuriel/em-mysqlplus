module EventMachine
  class MySQLConnection < EventMachine::Connection

    attr_reader :processing, :connected, :opts
    alias :settings :opts

    MAX_RETRIES_ON_DEADLOCKS = 10

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
      @queue = []
      @processing = false
      @connected = true

      self.notify_readable = true
      EM.add_timer(0){ next_query }
    end

    def notify_readable
      if item = @current
        sql, cblk, eblk, retries = item
        result = @mysql.get_result

        # kick off next query in the background
        # as we process the current results
        @current = nil
        @processing = false
        next_query

        cblk.call(result)
      else
        return close
      end

    rescue Mysql::Error => e

      if e.message =~ /Deadlock/ and retries < MAX_RETRIES_ON_DEADLOCKS
        @queue << [sql, cblk, eblk, retries + 1]
        @processing = false
        next_query

      elsif DisconnectErrors.include? e.message
        @queue << [sql, cblk, eblk, retries + 1]
        return close

      elsif cb = (eblk || @opts[:on_error])
        cb.call(e)
        @processing = false
        next_query

      else
        raise e
      end
    end

    def unbind
      @connected = false

      # wait for the next tick until the current fd is removed completely from the reactor
      #
      # in certain cases the new FD# (@mysql.socket) is the same as the old, since FDs are re-used
      # without next_tick in these cases, unbind will get fired on the newly attached signature as well
      #
      # do _NOT_ use EM.next_tick here. if a bunch of sockets disconnect at the same time, we want
      # reconnects to happen after all the unbinds have been processed

      # TODO: reconnect logic will / is broken with new code structure

      EM.add_timer(0) do
        @processing = false
        @mysql = EventedMysql._connect @opts
        @fd = @mysql.socket

        @signature = EM.attach_fd @mysql.socket, true
        EM.set_notify_readable @signature, true
        EM.instance_variable_get('@conns')[@signature] = self
        @connected = true
        next_query
      end
    end

    def execute(sql, cblk = nil, eblk = nil, retries = 0)
      begin
        if not @processing or not @connected
          @processing = true
          @mysql.send_query(sql)
        else
          @queue << [sql, cblk, eblk, retries]
          return
        end

      rescue Mysql::Error => e
        if DisconnectErrors.include? e.message
          @queue << [sql, cblk, eblk, retries]
          return close
        else
          raise e
        end
      end

      @current = [sql, cblk, eblk, retries]
    end
  
    def close
      @connected = false
      detach
    end

    private

    def next_query
      if @connected and !@processing and pending = @queue.shift
        sql, cblk, eblk = pending
        execute(sql, cblk, eblk)
      end
    end
 
  end
end