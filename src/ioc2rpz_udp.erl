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

%% @doc UDP DNS listener worker implemented as a gen_server.
%%
%% Each instance opens a UDP socket on port 53 (bound to a specific IP or
%% wildcard) and receives DNS packets via active-mode messaging. Incoming
%% packets are dispatched to {@link ioc2rpz:parse_dns_request/3} in a
%% spawned process so the listener is never blocked by query processing.

-module(ioc2rpz_udp).
-behaviour(gen_server).

-include_lib("ioc2rpz.hrl").

-export([start_ioc2rpz_udp/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% @doc Starts a linked UDP worker gen_server bound to the given IP and parameters.
%% Called by the supervisor to spawn a new UDP listener process.
%% @param IP The IP address to bind the UDP socket to, or an empty string for wildcard.
%% @param Params A list starting with the IP version atom (`inet' or `inet6') followed by additional parameters.
%% @returns `{ok, Pid}' on success.
start_ioc2rpz_udp(IP,Params) ->
  gen_server:start_link(?MODULE, [IP,Params], []).

%% @doc Initializes the UDP worker by opening a UDP socket on port 53.
%%
%% When `IP' is a non-empty string, the socket is bound to that specific
%% address. Otherwise it binds to all interfaces for the given IP version.
%%
%% Socket options:
%% <ul>
%%   <li>`binary' — receive packets as binaries</li>
%%   <li>`{active, true}' — deliver incoming packets as Erlang messages</li>
%%   <li>`{read_packets, 100}' — batch up to 100 packets per read for throughput</li>
%%   <li>`{recbuf, 65535}' — kernel receive buffer sized for DNS traffic</li>
%% </ul>
%%
%% @param IP The IP address to bind to, or empty string for wildcard.
%% @param Params List beginning with IP version (`inet' | `inet6').
%% @returns `{ok, State}' with the opened UDP socket stored in state.
init([IP,[IPver|_]=Params]) when IP /=""->
  {ok, UDPSocket} = gen_udp:open(53, [{ip, IP},IPver,binary, {active, true},{read_packets, 100},{recbuf, 65535}]),
  {ok, #state{socket=UDPSocket, params=Params}};

init([_IP,[IPver|_]=Params]) ->
  {ok, UDPSocket} = gen_udp:open(53, [IPver,binary, {active, true},{read_packets, 100},{recbuf, 65535}]),
  {ok, #state{socket=UDPSocket, params=Params}}.


%% @doc Handles a shutdown cast by closing the UDP socket and stopping normally.
handle_cast(shutdown, State) ->
%    io:format("Generic cast handler: *shutdown* while in '~p'~n",[State]),
  gen_udp:close(State#state.socket),
  {stop, normal, State};

%% @doc Ignores any unrecognised cast messages.
handle_cast(_Msg, State) ->
  {noreply, State}.

%% @doc Handles an incoming UDP DNS packet.
%%
%% Each packet is dispatched to a newly spawned process running
%% {@link ioc2rpz:parse_dns_request/3} so the listener is never blocked
%% by query processing. The `#proto{}' record carries the transport type
%% and the remote peer's IP/port for response routing.
%%
%% @param Socket The UDP socket that received the packet.
%% @param RIP    Remote peer IP address.
%% @param RPort  Remote peer port number.
%% @param Pkt    Raw DNS packet binary.
%% @returns `{noreply, State}'.
handle_info({udp, Socket, RIP, RPort, Pkt}, State) ->
    spawn(ioc2rpz,parse_dns_request,[Socket, Pkt, #proto{proto=udp, rip=RIP, rport=RPort}]),
    %ioc2rpz_fun:logMessage("get udp ~p ~p ~p ~n",[RIP, RPort, Pkt]),
    {noreply, State};

%% @doc Catches any unexpected messages and logs them for debugging.
handle_info(E, State) ->
  ioc2rpz_fun:logMessage("unexpected: ~p ~n", [E]),
  {noreply, State}.

%% @doc Catches any unrecognised call messages; returns `noreply' (no reply sent).
handle_call(_E, _From, State) ->
  {noreply, State}.

%% @doc Terminates the worker. No special cleanup is performed beyond
%% the normal gen_server shutdown sequence.
terminate(_Reason, _Tab) ->
%  ioc2rpz_db:tab2file([]),
  ok.

%% @doc Hot code upgrade callback. Returns the state unchanged.
code_change(_OldVersion, Tab, _Extra) ->
  {ok, Tab}.
