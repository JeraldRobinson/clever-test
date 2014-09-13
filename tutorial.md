### Building an App With Clever

Clever is a platform for building education applications. It provides an easy-to-use SSO platform and a powerful API for fetching aggregated student and school data. In the following tutorial, we'll walk through the steps for building a basic application leveraging the Clever Auth platform and API. The main topics we will focus on are authenticating your users with Clever using the Oauth protocol and retrieving user data from Clever's REST API.


#### Authenticating the user with clever
	
One of the most powerful features of Clever's platform is the ability to authenticate students and teachers from multiple districts via a single sign in flow. Clever allows this by providing an Oauth2 server. You can read about Oauth2 in excruciating detail in the IETF's [RFC](http://tools.ietf.org/html/rfc6749). 
	
__But in short there are 3 basic steps for authenticating a user with oauth:__
	1. Constructing a valid "login" link to Clever's oauth endpoint.
	2. Receiving a temporary authorization code from Clever (this is generally included as a parameter in a redirect to your server)
	3. Exchanging the temporary grant for an actual Oauth Token.
	
__To make the auth flow work we'll use a few pieces of info from Clever:__
	- Clever Client ID (public, assigned when you register your Clever app)
	- Clever Client Secret (secret, assigned when you register your Clever app)
	- redirect uri (public, configurable in clever's app console)
	
So with that said, let's get into it.

1. __Linking to Clever’s oauth server__

	The first part of the oauth flow consists of linking the user to clever’s authorization endpoint: https://clever.com/oauth/authorize. An example authorization link looks like:
	
	```
	https://clever.com/oauth/authorize?response_type=code&redirect_uri=http://localhost:9292/oauth&client_id=3bf626d60ba3b67546de&scope=read%3Auser_id%20read%3Astudents&district_id=5327a245c79f90670e001b78
	```	
	
	As you can see, there are a few key pieces of information included here:
	
	- The `client_id` [registered to your application by Clever](http://www.evernote.com/shard/s294/sh/ba2e4674-5103-44ed-bb0f-0898609005fc/4781700a89d6e9439b77482c369b5578).

	- The `redirect_uri`, where users will land after authenticating -- ideally something like <your_domain.com>/oauth. This URI must be [registered with Clever](http://www.evernote.com/shard/s294/sh/51c7827c-2f41-4ae2-acf7-edd17a410f44/827b7b0ad8498c46aa589517a43e4f30).

	- The access `scope` granted to your application, according to the Clever [app console](http://www.evernote.com/shard/s294/sh/262fc587-7468-45fc-8d12-36d63d7c68c1/bca10e108d9628e43c07ded71552b189).

	- the `district_id` to which you are planning to authorize the user.
	
	- `response_type` -- generally "code"

	By encoding these items as query params in a link to clever.com/oauth/authorize, you give Clever the info it needs to recognize your application, and to send the user back to you after they have authenticated.

2. __Handling authentication grants from Clever__

	After authenticating on Clever.com, the user is redirected back to the redirect URI you provided. An example redirect URI might look like:

	```
	http://localhost:9292/oauth?code=asdf123
	```

	This code parameter represents a temporary grant to authorize your application with the user's Clever account. To do this, you need to send a POST to clever's token endpoint: `https://clever.com/oauth/tokens`. This request takes a few parameters:

	- the `code` you received from clever; this identifies the user
	- `grant_type` -- so far Clever only supports “authorization_code” in this field
	- Your application's registered `redirect_uri`
	- Your Clever `client_id` and `client_secret`. These are includes as HTTP Basic Auth parameters, where `client_id` is username and `client_secret` is password. To send this data you Base64 ecode the string "`client_id`:`client_secret`, prepend `Basic ` and send it as an `Authorization` header (example below).
	
	This last component is key to oauth, as it’s what proves to Clever that your application is really who it says it is, and that the user in question has authenticated with the right service. Because of this it’s essential to keep your app’s client secret exactly that -- secret. Also note that you should always use https when sending this POST to clever. Failure to do so could allow man in the middle attackers to intercept your request and thus access your Client Secret. Finally, keep in mind that Base64 is merely an encoding convenience, not a cryptographic hashing algorithm, so it does not offer any protection against attacks.

	So that said, here's an example of what this request looks like in Ruby:

	```
	```

	and with curl:

	```
	```


	Assuming we did all of this correctly, Clever’s server will send back a response containing -- at long last! -- an oauth access token for the user. The response will be a json payload like so:

	```
	{“access_token”:”your_token”}
	```

	If something goes wrong, clever will send back some error information about the response. Some common errors are:

	- `invalid_grant` -- this means the code you sent to clever was either invalid or expired. make sure you included the exact code parameter they sent, and that you didn’t take too long in posting to clever.
	- `invalid redirect` -- make sure the redirect_uri you supplied matches what is on file in Clever’s app console. Watch for trailing slashes, http vs https, etc.

	Now that you’ve got a token, we can use it to do some stuff. Perhaps most exciting, you can retrieve the user’s data from Clever!

3. __Fetching the User’s Info from Clever’s API__

	The access_token returned by clever is what the Oauth system calls a “bearer token.” It proves to the system that you are authorized by the user to access their data, according to the permissions granted to your app. For our case, let’s use it to retrieve the newly-authenticated users’s Clever ID from the `me` endpoint.

	The request to do so would look like this:
	
	```
	```

	This gives back some assorted data about the user, similar to what could be retrieved from the “students” endpoint. So now we have authenticated the user with clever and fetched their basic info. But we’d also like to save some session state so we know that the user has authenticated and we don’t need to send them through oauth flow again on subsequent requests.

	A cookie will work well for this, but it brings up an interesting point about oauth. Oauth bearer tokens should be treated like cash -- if an attacker somehow grabs one, they can impersonate the user with few restrictions. For this reason it’s better to keep the token on your server (or not store it at all) and cookie the user with some other identifier. Since we just fetched the user’s info, including clever ID, we can save this to their session, and use it to identify them on subsequent requests:

	```
	``` 

	Finally, remember that the User’s current request was a redirect from Clever to our `/oauth` endpoint. This isn’t a particularly helpful place to leave them, so let’s send them back to the root where we can display some information.


4. __Using the API to Display a User’s Course Schedule__

	Now that our user has run through oauth flow, authenticated, and landed back on the root page of our simple web server, let’s pull in some data from Clever’s REST API to show their course schedule.

	We will be using data from two endpoints: the students endpoint, which will give us the user’s basic info, and the sections endpoint, which will give us their user’s schedule. Both of these endpoints take a student ID as input.

	For both of these requests, we will be authenticating via http basic auth with our clever API token. This can be a bit confusing, but the requirement is to send an “Authorization” header of the form “Basic <base64-encoded string of your API token + ‘:’>” (Standard HTTP Basic Auth header uses base64-encoded “username:password” string; we are using our API token as a username, and in this case we don’t have a password, which is why there is nothing after the colon).

	Here’s how that setup looks using Faraday in ruby:

	```
	```

	Now that our client is set up, lets fetch the user info and section info based on the student ID we saved in the user’s session:


	And display it in the UI:





worace @ Guinevere / ~ /  ➸  curl -v http://clever.com/oauth/tokens
* Adding handle: conn: 0x7fb480804400
* Adding handle: send: 0
* Adding handle: recv: 0
* Curl_addHandleToPipeline: length: 1
* - Conn 0 (0x7fb480804400) send_pipe: 1, recv_pipe: 0
* About to connect() to clever.com port 80 (#0)
*   Trying 54.183.45.34...
* Connected to clever.com (54.183.45.34) port 80 (#0)
> GET /oauth/tokens HTTP/1.1
> User-Agent: curl/7.30.0
> Host: clever.com
> Accept: */*
>
< HTTP/1.1 302 Found
< Cache-Control: no-cache
< Location: https://clever.com/oauth/tokens
< Content-Length: 0
< Connection: keep-alive
