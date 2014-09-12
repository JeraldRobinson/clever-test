require "./app"

require "clever-ruby"
require "rest-client"
require "byebug"

Clever.configure do |config|
  config.api_key = ENV["CLEVER_API_KEY"]
end
Clever::Student.retrieve("5327abf4831463c82497faa1")

run CleverDemo.new
