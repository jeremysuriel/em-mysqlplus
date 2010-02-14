$:.unshift(File.dirname(__FILE__) + '/../lib')

require "eventmachine"

%w[ mysql connection ].each do |file|
  require "em-mysql/#{file}"
end
