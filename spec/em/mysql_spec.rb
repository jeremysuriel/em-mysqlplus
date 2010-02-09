require 'rubygems'
require 'em/spec'
require File.dirname(__FILE__) + "/../../lib/em/mysql.rb"

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

EM.describe EventedMysql, 'connection pools' do

  EventedMysql.settings.update :connections => 3

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

# XXX this should get cleaned up automatically after reactor stops
SQL.reset!

EM.describe SQL, 'sql api' do
  
  should 'run a query on all connections' do
    SQL.all('use test'){
      :done.should == :done
      done
    }
  end
  
  should 'execute queries with no results' do
    SQL.execute('drop table if exists evented_mysql_test'){
      :table_dropped.should == :table_dropped
      SQL.execute('create table evented_mysql_test (id int primary key auto_increment, num int not null)'){
        :table_created.should == :table_created
        done
      }
    }
  end
  
  should 'insert rows and return inserted id' do
    SQL.insert('insert into evented_mysql_test (num) values (10),(11),(12)'){ |id|
      id.should == 1
      done
    }
  end

  should 'select rows from the database' do
    SQL.select('select * from evented_mysql_test'){ |res|
      res.size.should == 3
      res.first.should == { 'id' => '1', 'num' => '10' }
      res.last.should  == { 'id' => '3', 'num' => '12' }
      done
    }
  end

  should 'update rows and return affected rows' do
    SQL.update('update evented_mysql_test set num = num + 10'){ |changed|
      changed.should == 3
      done
    }
  end

  should 'allow access to insert_id in raw mode' do
    SQL.raw('insert into evented_mysql_test (num) values (20), (21), (22)'){ |mysql|
      mysql.insert_id.should == 4
      done
    }
  end

  should 'allow access to affected_rows in raw mode' do
    SQL.raw('update evented_mysql_test set num = num + 10'){ |mysql|
      mysql.affected_rows.should == 6
      done
    }
  end

  should 'fire error callback with exceptions' do
    SQL.settings.update :on_error => proc{ |e|
      e.class.should == Mysql::Error
      done
    }
    SQL.select('select 1+ from table'){}
  end

end
