require 'helper'

describe EventMachine::MySQL do
  it "should create a new connection"
  it "should reconnect when disconnected"
  it "should execute sql"
  it "run select queries and return results"
  it "queue up queries and execute them in order"
  it "have raw mode which yields the mysql object"
  it "allow custom error callbacks for each query"
end

__END__

EM.describe EventedMysql, 'individual connections' do

  should 'create a new connection' do
    @mysql = EventedMysql.connect :host => '127.0.0.1',
      :port => 3306,
      :database => 'test',
      :logging => false

    @mysql.class.should == EventedMysql
    done
  end

  should 'connect to another host if the first one is not accepting connection' do
    @mysql = EventedMysql.connect({:host => 'unconnected.host',
                                   :port => 3306,
                                   :database => 'test',
                                   :logging => false},
                                  { :host => '127.0.0.1',
                                    :port => 3306,
                                    :database => 'test',
                                    :logging => false })

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

  should 'reconnect when disconnected' do
    @mysql.close
    @mysql.execute('select 1+2'){
      :connected.should == :connected
      done
    }
  end

  # to test, run:
  #   mysqladmin5 -u root kill `mysqladmin5 -u root processlist | grep "select sleep(5)+1" | cut -d'|' -f2`
  #
  # should 're-run query if disconnected during query' do
  #   @mysql.execute('select sleep(5)+1', :select){ |res|
  #     res.first['sleep(5)+1'].should == '1'
  #     done
  #   }
  # end

  should 'run select queries and return results' do
    @mysql.execute('select 1+2', :select){ |res|
      res.size.should == 1
      res.first['1+2'].should == '3'
      done
    }
  end

  should 'queue up queries and execute them in order' do
    @mysql.execute('select 1+2', :select)
    @mysql.execute('select 2+3', :select)
    @mysql.execute('select 3+4', :select){ |res|
      res.first['3+4'].should == '7'
      done
    }
  end

  should 'continue processing queries after hitting an error' do
    @mysql.settings.update :on_error => proc{|e|}

    @mysql.execute('select 1+ from table'){}
    @mysql.execute('select 1+1 as num', :select){ |res|
      res[0]['num'].should == '2'
      done
    }
  end

  should 'have raw mode which yields the mysql object' do
    @mysql.execute('select 1+2 as num', :raw){ |mysql|
      mysql.should.is_a? Mysql
      mysql.result.all_hashes.should == [{'num' => '3'}]
      done
    }
  end

  should 'allow custom error callbacks for each query' do
    @mysql.settings.update :on_error => proc{ should.flunk('default errback invoked') }

    @mysql.execute('select 1+ from table', :select, proc{
                     should.flunk('callback invoked')
                   }, proc{ |e|
                     done
    })
  end

end
