require "base64"
require "sinatra"
require "faraday"
require "json"
class CleverDemo < Sinatra::Base
  OAUTH_REDIRECT_URI = "https://obscure-bastion-5205.herokuapp.com/oauth"
  #OAUTH_REDIRECT_URI = "http://localhost:9292/oauth"
  use Rack::Session::Cookie, :expire_after => 102592000

  get "/" do
    logger.info "getting root"
    logger.info env["rack.session.options"].inspect
    @info = student_info(session["clever_id"]) if session["clever_id"]
    erb :schedule
  end

  get "/oauth" do
    retrieve_clever_auth_token
    redirect "/"
  end

  get "/logout" do
    session.clear
    redirect "/"
  end

  def student_info(student_id)
    resp = clever_client.get("/v1.1/students/#{student_id}")
    if resp.success?
      JSON.parse(resp.body).merge("valid" => true)
    else
      {"valid" => false}
    end
  end

  def clever_client
    Faraday.new(:url => 'https://api.clever.com') do |builder|
      builder.adapter  Faraday.default_adapter
      builder.headers["Authorization"] = "Basic #{Base64.encode64(ENV["CLEVER_API_KEY"]+":")}"
    end
  end

  def me_info(token)
    conn = Faraday.new(:url => 'https://api.clever.com') do |builder|
      builder.adapter  Faraday.default_adapter
    end
    conn.headers["Authorization"] = "Bearer #{token}"
    info = conn.get("/me").body
    JSON.parse(info)
  end

  def code_params
    {"code" => params[:code],"grant_type" => "authorization_code","redirect_uri" => OAUTH_REDIRECT_URI}
  end

  def retrieve_clever_auth_token
    conn = Faraday.new(:url => 'https://clever.com') do |builder|
      builder.use Faraday::Request::UrlEncoded
      auth_string = Base64.encode64("#{ENV["CLEVER_CLIENT_ID"]}:#{ENV["CLEVER_CLIENT_SECRET"]}").gsub("\n","")
      builder.headers["Authorization"] = "Basic #{auth_string}"
      builder.adapter  Faraday.default_adapter
    end
    response = conn.post("/oauth/tokens", code_params)
    if stuff.success?
      token = JSON.parse(stuff.body)["access_token"]
      session["clever_id"] = me_info(token)["data"]["id"]
    else
      response stuff.body.to_s
    end
  end

  def sections(id)
    @sections ||= Clever::Student.retrieve(id).sections
  end

  def session
    env["rack.session"]
  end

  def clever_auth_url
    "https://clever.com/oauth/authorize?response_type=code&redirect_uri=#{OAUTH_REDIRECT_URI}&client_id=#{ENV["CLEVER_CLIENT_ID"]}&scope=read%3Auser_id%20read%3Astudents&district_id=#{districts.first.id}"
  end

  def districts
    @districts ||= Clever::District.all
  end
end
