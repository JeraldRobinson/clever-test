require "./app"
require "clever-ruby"

Clever.configure do |config|
  config.api_key = ENV["CLEVER_API_KEY"]
end

run CleverDemo.new
