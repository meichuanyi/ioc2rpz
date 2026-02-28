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

%% @doc Database ownership supervisor for ioc2rpz.
%%
%% A `gen_server' process that acts as the heir for ETS tables used by
%% ioc2rpz. When a process that owns an ETS table terminates, ownership
%% is transferred to this supervisor via `ETS-TRANSFER' messages,
%% preventing table loss on process crashes.
%% @end
-module(ioc2rpz_db_sup).
-behaviour(gen_server).

-export([start_db/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% @doc Start and link the database supervisor process.
%% @end
start_db() ->
  gen_server:start_link(?MODULE, [], []).

%% @doc Initialize the gen_server with an empty state.
%% @end
init(_Init) ->
	{ok, []}.

%% @doc Handle ETS table ownership transfer.
%%
%% When a process owning an ETS table terminates, the table is
%% transferred to this process via `ETS-TRANSFER'. Logs the table
%% name and accepts ownership.
%% @end
handle_info({'ETS-TRANSFER',Tab,_FromPid,_GiftData}, _State) ->
  ioc2rpz_fun:logMessage("DB_sup got ~p table ownership ~n", [Tab]),
  {noreply, ok};

%% @doc Handle unexpected info messages.
%% @end
handle_info(Info, State) ->
  ioc2rpz_fun:logMessage("DB_sup got an unmached handle_info request:~p ~n", [Info]),
  {noreply, State}.

%% @doc Handle cast messages (unused).
%% @end
handle_cast(_Msg, State) ->
    {noreply, State}.

%% @doc Handle call messages (unused).
%% @end
handle_call(_E, _From, State) ->
  {noreply, State}.

%% @doc Clean up on termination.
%% @end
terminate(_Reason, _Tab) ->
%  ioc2rpz_db:tab2file([]),
  ok.

%% @doc Handle hot code upgrades.
%% @end
code_change(_OldVersion, Tab, _Extra) ->
  {ok, Tab}.
