$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'active_record/connection_adapters/em_mysqlplus_adapter'
require 'active_record/patches'