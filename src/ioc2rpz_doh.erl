%Copyright 2017-2021 Vadim Pavlov ioc2rpz[at]gmail[.]com
%
%Licensed under the Apache License, Version 2.0 (the "License");
%you may not use this file except in compliance with the License.
%You may obtain a copy of the License at
%
%    http://www.apache.org/licenses/LICENSE-2.0
%
%Unless required by applicable law or agreed to in writing, software
%distributed under the License is distributed on an "AS IS" BASIS,
%WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%See the License for the specific language governing permissions and
%limitations under the License.

%% @doc DNS-over-HTTPS (DoH) handler module.
%%
%% Implements RFC 8484 DNS-over-HTTPS using the Cowboy REST behaviour.
%% Supports both GET (base64url-encoded `dns' query parameter) and POST
%% (`application/dns-message' body) methods. Incoming DNS wire-format
%% messages are decoded and forwarded to {@link ioc2rpz:parse_dns_request/3}
%% for processing; the binary DNS response is returned with content type
%% `application/dns-message'.
%% @end
-module(ioc2rpz_doh).
-include_lib("eunit/include/eunit.hrl").

-include_lib("ioc2rpz.hrl").

-export([init/2, allowed_methods/2, content_types_accepted/2, content_types_provided/2,parse_dns/2]).

%% @doc Cowboy REST `init/2' callback.
%%
%% Extracts the operation atom from the route options and stores it in
%% a `#state{}' record. Returns `{cowboy_rest, Req, State}' to
%% enter the Cowboy REST state machine.
%%
%% @param Req  Cowboy request object.
%% @param Opts Route options list; the first element is the operation atom.
%% @returns `{cowboy_rest, Req, #state{}}' tuple.
%% @end
init(Req, Opts) ->
    [Op | _] = Opts,
    State = #state{op=Op},
    {cowboy_rest, Req, State}.

%% @doc Return the list of allowed HTTP methods for the DoH endpoint.
%% @end
allowed_methods(Req, State) ->
    Methods = [<<"GET">>, <<"POST">>],
    {Methods, Req, State}.

%% @doc Declare accepted content types for POST requests.
%%
%% Only `application/dns-message' is accepted, mapped to {@link parse_dns/2}.
%% @end
content_types_accepted(Req, State) ->
    {[
      {<<"application/dns-message">>, parse_dns}
     ], Req, State}.

%% @doc Declare provided content types for GET responses.
%%
%% Responses are served as `application/dns-message', handled by
%% {@link parse_dns/2}.
%% @end
content_types_provided(Req, State) ->
    {[
      {<<"application/dns-message">>, parse_dns}
     ], Req, State}.

%% @doc Parse a DNS-over-HTTPS GET request.
%%
%% Extracts the `dns' query-string parameter, base64url-decodes it into
%% a DNS wire-format binary, and delegates to {@link parse_dns/3}.
%% Returns `{error, <<>>}' when the parameter is missing or empty.
%%
%% @param Req   Cowboy request with `method => <<"GET">>'.
%% @param State Current handler state.
%% @end
parse_dns(#{method := Method} = Req, State) when Method == <<"GET">> ->
	DNSMessage = case cowboy_req:match_qs([{dns, [], <<>>}], Req) of
	  #{dns := <<>>} -> {error,<<>>};
		#{dns := DNSQ} -> ioc2rpz_fun:base64url_decode(DNSQ)
	end,
	parse_dns(Req, State, DNSMessage);

%% @doc Parse a DNS-over-HTTPS POST request.
%%
%% Reads the full request body via {@link read_body/2} (expected to be a
%% raw DNS wire-format message with content type `application/dns-message')
%% and delegates to {@link parse_dns/3}. Returns `{error, <<>>}' when the
%% request has no body.
%%
%% @param Req   Cowboy request with `method => <<"POST">>'.
%% @param State Current handler state.
%% @end
parse_dns(#{method := Method} = Req, State) when Method == <<"POST">> ->
	DNSMessage = case cowboy_req:has_body(Req) of
		true -> {ok,DNSM,Req0} = read_body(Req,<<>>),{ok,DNSM};
		_ -> Req0=Req, {error, <<>>}
	end,
	parse_dns(Req0, State, DNSMessage).

%% @doc Handle a malformed or missing DNS message.
%%
%% Logs the bad request with the peer's IP/port and request URI, then
%% replies with HTTP 400 Bad Request.
%% @end
parse_dns(Req, State, {error, <<>>}) ->
	#{peer := {IP, Port}} = Req,
	ioc2rpz_fun:logMessage("Bad request from ~p:~p. URI: ~p\n",[ioc2rpz:ip_to_str(IP), Port, cowboy_req:uri(Req)]),
	{normal,cowboy_req:reply(400,#{}, "Bad request\n", Req),State};

%% @doc Process a valid DNS wire-format message received over HTTPS.
%%
%% Forwards the decoded DNS binary to {@link ioc2rpz:parse_dns_request/3}
%% using the `doh' protocol tag. On success the binary DNS response is
%% returned to Cowboy for serialisation; on failure a 400 reply is sent.
%%
%% @param Req        Cowboy request object.
%% @param State      Current handler state.
%% @param DNSMessage `{ok, Binary}' containing the raw DNS wire-format query.
%% @end
parse_dns(Req, State, {ok, DNSMessage}) ->
	#{peer := {IP, Port}} = Req,
	ioc2rpz_fun:logMessage("DNS request from ~p:~p. ~p Host: ~p, Path: ~p. Message ~p\n",[ioc2rpz:ip_to_str(IP), Port, cowboy_req:method(Req), cowboy_req:host(Req), cowboy_req:path(Req), DNSMessage]),
	Respond = case ioc2rpz:parse_dns_request(<<>>, DNSMessage, #proto{proto=doh, rip=IP, rport=Port}) of
		{ok, Data} -> {Data, Req, State};
		_ -> Req0=cowboy_req:reply(400,#{}, "Bad request\n", Req), {normal, Req0, State}
	end,
	Respond.

%% @doc Read the full request body, accumulating chunks.
%%
%% Calls `cowboy_req:read_body/1' in a loop, concatenating each chunk
%% into `Acc' until Cowboy signals `ok' (final chunk). Used by the POST
%% handler to collect the raw DNS wire-format message.
%%
%% @param Req0 Cowboy request object (updated after each read).
%% @param Acc  Accumulator binary for body data read so far.
%% @returns `{ok, Body, Req}' when the entire body has been read.
%% @end
read_body(Req0, Acc) ->
    case cowboy_req:read_body(Req0) of
        {ok, Data, Req} -> {ok, << Acc/binary, Data/binary >>, Req};
        {more, Data, Req} -> read_body(Req, << Acc/binary, Data/binary >>)
    end.
