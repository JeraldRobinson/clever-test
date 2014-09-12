require "sinatra"
require "faraday"
require "json"
class CleverDemo < Sinatra::Base
  OAUTH_REDIRECT_URI = "http://localhost:9292/oauth"
  use Rack::Session::Cookie, :expire_after => 102592000

  get "/" do
    logger.info "getting root"
    logger.info env["rack.session.options"].inspect
    @info = me_info if session["clever_id"]
    @districts = Clever::District.all
    erb :schedule
  end

  get "/oauth" do
    faraday_wtf
    redirect "/"
  end

  def me_info
    conn = Faraday.new(:url => 'https://api.clever.com') do |builder|
      builder.adapter  Faraday.default_adapter
    end
    conn.headers["Authorization"] = "Bearer #{session["clever_id"]}"
    info = conn.get("/me").body
    JSON.parse(info)
  end

  def code_params
    {"code" => params[:code],"grant_type" => "authorization_code","redirect_uri" => OAUTH_REDIRECT_URI}
  end

  def faraday_wtf
    conn = Faraday.new(:url => 'https://clever.com') do |builder|
      builder.use Faraday::Request::UrlEncoded
      #Q: could never make this work with curl -- research in gem?
      builder.basic_auth(ENV["CLEVER_CLIENT_ID"], ENV["CLEVER_CLIENT_SECRET"])
      builder.adapter  Faraday.default_adapter
    end
    stuff = conn.post("/oauth/tokens", code_params)
    if stuff.success?
      session["clever_id"] = JSON.parse(stuff.body)["access_token"]
    else
      raise stuff.body.to_s
    end
  end

  def sections(id)
    @sections ||= Clever::Student.retrieve(id).sections
  end

  def session
    env["rack.session"]
  end
end
