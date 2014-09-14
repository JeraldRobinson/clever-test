require "sinatra"
require "uri"
require "base64"
require "active_support/core_ext/hash"# for Hash#to_query
require "faraday"
require "json"

class CleverDemo < Sinatra::Base
  CLEVER_ROOT = "https://clever.com"
  CLEVER_REDIRECT_URI = "https://obscure-bastion-5205.herokuapp.com/oauth"
  use Rack::Session::Cookie, :expire_after => 102592000,
                             :secret => ENV["CLEVER_DEMO_COOKIE_SECRET"]

  ## ENDPOINTS

  get "/" do
    if session["clever_id"]
      @student_info = student_info(session["clever_id"])
      @sections = student_sections(session["clever_id"])
      erb :schedule
    else
      "<a href='#{clever_auth_url}'>Log in with Clever!</a>"
    end
  end

  get "/oauth" do
    conn = Faraday.new(:url => CLEVER_ROOT) do |builder|
      builder.use Faraday::Request::UrlEncoded
      builder.headers["Authorization"] = "Basic #{clever_basic_auth_string}"
      builder.adapter  Faraday.default_adapter
    end
    code_params = {"code" => params[:code],
                   "grant_type" => "authorization_code",
                   "redirect_uri" => CLEVER_REDIRECT_URI}
    response = conn.post("/oauth/tokens", code_params)

    if response.success?
      token = JSON.parse(response.body)["access_token"]
      session["clever_id"] = me_info(token)["data"]["id"]
      redirect "/"
    else
      "<p>#{response.body.to_s}</p><p><a href='/'>home</a></p>"
    end
  end

  get "/logout" do
    session.clear
    redirect "/"
  end

  ## SUPPORT

  def student_info(student_id)
    resp = clever_client.get("/v1.1/students/#{student_id}")
    if resp.success?
      JSON.parse(resp.body).merge("valid" => true)
    else
      {"valid" => false}
    end
  end

  def student_sections(student_id)
    response = clever_client.get("/v1.1/students/#{student_id}/sections")
    if response.success?
      JSON.parse(response.body)["data"].map do |section|
        section["data"]
      end.sort_by do |section|
        section["period"].to_i
      end
    else
      "error: #{response.body}"
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
      builder.headers["Authorization"] = "Bearer #{token}"
    end
    JSON.parse(conn.get("/me").body)
  end

  def clever_auth_url
    URI(CLEVER_ROOT).tap do |uri|
      uri.path = "/oauth/authorize"
      uri.query = clever_auth_params.to_query
    end
  end

  def clever_auth_params
    {
      "client_id" => ENV["CLEVER_CLIENT_ID"],
      "redirect_uri" => CLEVER_REDIRECT_URI,
      "response_type" => "code",
      "scope" => "read:user_id read:student",
      "district_id" => "5327a245c79f90670e001b78"
    }
  end

  def clever_api_token_auth_string
    Base64.encode64("#{ENV["CLEVER_API_KEY"]}:")
  end

  def clever_basic_auth_string
    Base64.encode64("#{ENV["CLEVER_CLIENT_ID"]}:#{ENV["CLEVER_CLIENT_SECRET"]}").gsub("\n","")
  end
end
