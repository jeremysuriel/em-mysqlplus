$:.unshift(File.dirname(__FILE__) + '/../lib')

require "eventmachine"

#%w[ backend proxy connection ].each do |file|
#  require "em-proxy/#{file}"
#end



module EventMachine
  class MySQL
  end
end
