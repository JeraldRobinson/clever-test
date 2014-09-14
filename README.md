### Building an App With Clever

Clever is a platform for building education applications. It provides an easy-to-use SSO platform and a powerful API for fetching aggregated student and school data. In the following tutorial, we'll walk through the steps for building a basic application leveraging the Clever Auth platform and API. The main topics we will focus on are authenticating your users with Clever using Oauth and retrieving user data from Clever's REST API.

#### Authenticating the user with clever
	
Clever's auth platform is an implementation of the Oauth2 protocol. Interacting with the auth server is not too complicated, but there are several steps involved and it's important to get the details right.
	
__Steps for authenticating users with Clever:__

	1. Constructing a valid "login" link to Clever's oauth endpoint. (This will take the user away from your site momentarily so they can login with Clever)
	2. Receiving a temporary authorization code from Clever (this is generally included as a parameter in a redirect to your server)
	3. Exchanging the temporary grant for an actual Oauth Token via Clever's token API.
	
__To make the auth flow work we'll use a few pieces of info from Clever:__

	- Clever Client ID (public, assigned when you register your Clever app)
	- Clever Client Secret (secret, assigned when you register your Clever app)
	- redirect uri (public, configurable in clever's app console)

A quick note about working with these Clever credentials: while you could simply embed these in source, it's best to anonymize them. An easy way to do this is by exporting them to your shell environment. For example:

```
export CLEVER_CLIENT_ID=your_id
export CLEVER_CLIENT_SECRET=your_secret
export CLEVER_API_KEY=your_key
```

Then you can access them in your code: `ENV["CLEVER_CLIENT_ID"]` (Ruby)

So with that said, let's get our user's authenticated. I'll be showing code examples for a simple web server implementation using Ruby's Sinatra library, but the principles will apply to any language or framework.

1. __Linking to Clever’s oauth server__

	The first part of the oauth flow consists of linking the user to clever’s authorization endpoint (`https://clever.com/oauth/authorize`). An example authorization link looks like:
	
	```
	https://clever.com/oauth/authorize?response_type=code&redirect_uri=http://localhost:9292/oauth&client_id=3bf626d60ba3b67546de&scope=read%3Auser_id%20read%3Astudents&district_id=5327a245c79f90670e001b78
	```	
	
	As you can see, there are a few key pieces of information included here:
	
	- The `client_id` [registered to your application by Clever](http://www.evernote.com/shard/s294/sh/ba2e4674-5103-44ed-bb0f-0898609005fc/4781700a89d6e9439b77482c369b5578).

	- The `redirect_uri`, where users will land after authenticating -- ideally something like <your_domain.com>/oauth. This URI must be [registered with Clever](http://www.evernote.com/shard/s294/sh/51c7827c-2f41-4ae2-acf7-edd17a410f44/827b7b0ad8498c46aa589517a43e4f30). Note that Clever allows you to register multiple URLs here, so you can include one for development and one for production.

	- The access `scope` granted to your application, according to the Clever [app console](http://www.evernote.com/shard/s294/sh/262fc587-7468-45fc-8d12-36d63d7c68c1/bca10e108d9628e43c07ded71552b189).

	- The `district_id` to which you are planning to authorize the user. If your application deals with multiple districts, you will need to determine this dynamically. Since we only have a single district for our demo app, we will just be hardcoding this.
	
	- `response_type` -- generally "code"

	By encoding these items as query params in a link to clever.com/oauth/authorize, you give Clever the info it needs to recognize your application, and to send the user back to you after they have authenticated. Let's add a basic HTTP endpoint which shows this link to our users:
	
		require "sinatra"
		require "active_support/core_ext/hash" #for Hash#to_query
		require "uri"

		CLEVER_ROOT = "https://clever.com"
		CLEVER_REDIRECT_URI = "http://localhost:9292/oauth"

		get "/" do
			"<a href='#{clever_auth_url}'>Log in with Clever!</a>"
		end
	
		def clever_auth_url
	  		URI(CLEVER_ROOT).tap do |uri|
	    		uri.query = clever_auth_params.to_query
	  		end
		end
	
		def clever_auth_params
	 		{
	  		"client_id" => ENV["CLEVER_CLIENT_ID"],
		    "redirect_uri" => CLEVER_REDIRECT_URI,
		    "response_type" => "code",
		    "scope" => "read:user_id read:student"
			}
		end
	
	By clicking this link, the user is taken to clever.com, presented with a login UI, and, if they authenticate successfully, redirected back to our site at `/oauth`. Currently we aren't doing anything to handle this request, so let's look at that in the next step.
	
2. __Handling authentication grants from Clever__

	When Clever sends the user back to your site, they'll include a special `code` parameter. An example redirect URI might look like:

	```
	http://localhost:9292/oauth?code=asdf123
	```

	This code parameter represents a temporary grant to authorize your application with the user's Clever account. To do this, you need to send a POST to clever's token endpoint: `https://clever.com/oauth/tokens`. This request takes a few parameters:

	- the `code` you received from clever; this identifies the user
	- `grant_type` -- so far Clever only supports “authorization_code” in this field
	- Your application's registered `redirect_uri`
	- Your Clever `client_id` and `client_secret`. These are includes as HTTP Basic Auth parameters, where username is your `client_id` and password is your `client_secret`. Some HTTP libraries support basic auth directly, but you can also send thes credentials as n `Authorization` header. The format is to Base64 ecode the string "`client_id`:`client_secret` (example below).
	
	Bear in mind that Base64 is merely an encoding convenience, not a cryptographic hashing algorithm. To protect yourself against MITM attacks that could expose your client secret, make sure to always send requests to Clever over HTTPS.

	So that said, here's what handling the `/oauth` request and exchanging the code looks like in our Sinatra app. We will be using Ruby's Faraday library to make the request to Clever's token endpoint.

	```
	require "json"
	....
	def clever_basic_auth_string
	  Base64.encode64("#{ENV["CLEVER_CLIENT_ID"]}:#{ENV["CLEVER_CLIENT_SECRET"]}").gsub("\n","")
	end
	
	get "/oauth" do
	  conn = Faraday.new(:url => CLEVER_ROOT) do |builder|
	    builder.use Faraday::Request::UrlEncoded
	    builder.headers["Authorization"] = "Basic #{clever_basic_auth_string}"
	    builder.adapter  Faraday.default_adapter
	  end
	  code_params = {"code" => params[:code], "grant_type" => "authorization_code","redirect_uri" => CLEVER_REDIRECT_URI}
	  response = conn.post("/oauth/tokens", code_params)
	
	  if response.success?
	    "<p>Congrats, you logged in!</p>
	     <p>token: #{JSON.parse(response.body)["access_token"]}</p>
	     <p><a href='/'>home</a></p>"
	  else
	    "<p>#{response.body.to_s}</p><p><a href='/'>home</a></p>"
	  end	    
	end
	```

	Note that Clever provides the access token as a JSON payload, and we are capturing it above. Additionally, if something goes wrong, Clever will send error information in the response. Some common errors are:

	- `invalid_grant` -- this means the code you sent to clever was either invalid or expired. make sure you included the exact code parameter they sent, and that you didn’t take too long in posting to clever. Since we so far haven't implemented any persistence of user credentials, this will likely happen if you refresh the `/oauth` request after a few moments. 
	- `invalid redirect` -- make sure the redirect_uri you supplied matches what is on file in Clever’s app console. Watch for trailing slashes, http vs https, etc.

	Now that you’ve got a token, we can use it retrieve our user's data from Clever!
	
#### Working With Clever's Rest API

1. __Fetching the User’s Info from Clever’s API__

	The access_token returned by Clever is what the Oauth system calls a “bearer token.” It proves to the system that you are authorized by the user to access their data, according to the permissions granted to your app. For our case, let’s use it to retrieve the newly-authenticated users’s Clever ID from the `me` endpoint, which contains their basic info.

	In Ruby, the request to do so would look like this:
	
	```
	  def me_info(token)
	    conn = Faraday.new(:url => 'https://api.clever.com') do |builder|
	      builder.adapter  Faraday.default_adapter
	      builder.headers["Authorization"] = "Bearer #{token}"
	    end
	    JSON.parse(conn.get("/me").body)
	  end
	```
	
	Let's do this in our `/oauth` endpoint after we handle the user's authentication:
	
	```
	get "/oauth" do
	  ...	
	  if response.success?
	    token = JSON.parse(response.body)["access_token"]
	    "<p>Congrats, you logged in!</p>
	     <p>token: #{token}</p>
	     <p><a href='/'>home</a></p>
	     <p>Here's your info: #{me_info(token)}"
	     ...
	  else
	    "<p>#{response.body.to_s}</p><p><a href='/'>home</a></p>"
	  end	    
	end
	```

	So now we have authenticated the user with clever and fetched their basic info. But you probably noticed if you refresh the page after a few moments you get an "expired grant" error. We need to save this authentication info so we don't have to re-authenticate them a new `code` every request. Let's save the user's Clever ID in their session, so we can identify them on subsequent requests. Finally, instead of leaving our user on the `/oauth` endpoint, lets redirect them back to home, and add some logic there to display different info for our logged in users.

	```
	enable :sessions
	
	get "/" do
	  if session["clever_id"]
	    "Hi, Student #{session["clever_id"]}"
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
	  code_params = {"code" => params[:code],"grant_type" => "authorization_code","redirect_uri" => CLEVER_REDIRECT_URI}
	  response = conn.post("/oauth/tokens", code_params)
	
	  if response.success?
	    token = JSON.parse(response.body)["access_token"]
	    session["clever_id"] = me_info(token)["data"]["id"]
	    redirect "/"
	  else
	    "<p>#{response.body.to_s}</p><p><a href='/'>home</a></p>"
	  end
	end
	```
	
	One last note about Oauth tokens -- these are the "cash" of the Oauth protocol. An attacker who captures a user's token is able to masquerade as them with impunity. For this reason, it's better to identify users with less sensitive data like a Clever ID or other UUID you create rather than, for example, persisting the Oauth token itself in a user session. 

2. __Using the API to Display a User’s Course Schedule__

	Now that our user has run through oauth flow, authenticated, and landed back on the root page of our simple web server, let’s pull in some data from Clever’s REST API to show their course schedule.

	We will be using data from two endpoints: the students endpoint, which will give us the user’s basic info (similar to what we fetched from `/me` before), and the sections endpoint, which will give us their schedule. Both of these endpoints take a student ID as input.

	For both of these requests, we will be authenticating via http basic auth with our clever API token. Similar to the Oauth request we made before, we will be sending HTTP Basic Auth credentials as an `Authorization` header. This time the username is our API key, and there is no password, so the header looks like: `Basic <base64-encoded string of your API token + ‘:’>`

	Here’s how that setup looks using Faraday: 

	```
	def clever_client
	  Faraday.new(:url => 'https://api.clever.com') do |builder|
	    builder.adapter  Faraday.default_adapter
	    builder.headers["Authorization"] = "Basic #{clever_api_token_auth_string}"
	  end
	end
	
	def clever_api_token_auth_string
      Base64.encode64("#{ENV["CLEVER_API_KEY"]}:")
	end
	```

	Now that our client is set up, lets fetch the user info and section info based on the student ID we saved in the user’s session:
	
	```
	def student_info(student_id)
	  response = clever_client.get("/v1.1/students/#{student_id}")
	  if response.success?
	    JSON.parse(response.body)
	  else
	    "error: #{response.body}"
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
	```

	Finally let's use this data to show the user their schedule. Since this UI is getting a bit more complicated, let's add a template in `views/schedule.erb`and do our rendering there. Now our root action will look like:
	
	```
	get "/" do
	  if session["clever_id"]
	    @student_info = student_info(session["clever_id"])
	    @sections = student_sections(session["clever_id"])
        erb :schedule
      else
        "<a href='#{clever_auth_url}'>Log in with Clever!</a>"
      end
    end
	```
	
	and the schedule (`views/schedule.erb`) template will look like:
	
	```
	<p>Hi, <%= @student_info["data"]["name"]["first"] %></p>
	<p>Here's your schedule:</p>
	<table>
	  <tr>
	    <th>Class Name</th>
	    <th>Period</th>
	  </tr>
	  <% @sections.each do |section| %>
	    <tr>
	      <td><%=section["name"]%></td>
	      <td><%=section["period"]%></td>
	    </tr>
	  <% end %>
	</table>
	```
	
	You should end up with a simple list of sections, ordered by period: https://www.evernote.com/shard/s294/sh/308afe26-422b-4325-a04e-8e95b8750fbd/371abdbbb25342d186574d5dc3ce8604
	
	Finally, let's give our users the ability to logout. This can be done with another route (I will use "/logout"), which simply clears the user's session and redirects them back to root:
	
	```
	get "/logout" do
	  session.clear
	  redirect "/"
	end
	```
	
	We can display this to logged in users by adding a line to our `schedule.erb` template:
	
	```
	...
	<p><a href="/logout">log out</a></p>
	```
	
	This simple application demonstrates the basic framework for dealing with Clever's Auth Platform and API. The "students" and "sections" endpoints we used here represent only a tiny fraction of the data Clever makes available. To find out more about what's available, check out the [interactive API explorer](https://clever.com/developers/docs/explorer). Finally a tidied-up version of this example application can be found here: (), and running on heroku at (). (Note that if you want to deploy to heroku, you'll need to use their [config management system](https://devcenter.heroku.com/articles/config-vars) tp store your API credentials).
	
	Happy Clever-ing!
	