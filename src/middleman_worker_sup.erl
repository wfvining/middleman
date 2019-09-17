%%%-------------------------------------------------------------------
%%% @author Will Vining <wfvining@gmail.com>
%%% @copyright (C) 2019, Will Vining
%%% @doc
%%%
%%% @end
%%% Created : 15 Sep 2019 by Will Vining <wfvining@gmail.com>
%%%-------------------------------------------------------------------
-module(middleman_worker_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, Pid :: pid()} |
                      {error, {already_started, Pid :: pid()}} |
                      {error, {shutdown, term()}} |
                      {error, term()} |
                      ignore.
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).


%%--------------------------------------------------------------------
%% @doc
%% Start a new middleman server
%% @end
%%--------------------------------------------------------------------
start_middleman() ->
    supervisor:start_child().

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart intensity, and child
%% specifications.
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) ->
                  {ok, {SupFlags :: supervisor:sup_flags(),
                        [ChildSpec :: supervisor:child_spec()]}} |
                  ignore.
init([]) ->

    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 1,
                 period => 5},

    AChild = #{id => middleman,
               start => {middleman_worker, start_link, []},
               restart => temporary,
               shutdown => 5000,
               type => worker,
               modules => [middleman_worker]},

    {ok, {SupFlags, [AChild]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
