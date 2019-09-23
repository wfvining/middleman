%%%-------------------------------------------------------------------
%%% @author Will Vining <wfvining@gmail.com>
%%% @copyright (C) 2019, Will Vining
%%% @doc
%%%
%%% Registry of middlemen. Provides a mapping from names to PIDs of
%%% middleman_worker servers.
%%%
%%% @end
%%% Created : 15 Sep 2019 by Will Vining <wfvining@gmail.com>
%%%-------------------------------------------------------------------
-module(middleman_registry).

-behaviour(gen_server).

%% API
-export([start_link/0, get/1, remove/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-define(SERVER, ?MODULE).

-record(state, {middlemen = #{}, refs = #{}}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, Pid :: pid()} |
                      {error, Error :: {already_started, pid()}} |
                      {error, Error :: term()} |
                      ignore.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec get(Name :: term()) -> {ok, pid()}.
get(Name) ->
    gen_server:call(?SERVER, {get_middleman, Name}).

-spec remove(Name :: term()) -> ok.
remove(Name) ->
    gen_server:cast(?SERVER, {remove_middleman, Name}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) -> {ok, State :: term()} |
                              {ok, State :: term(), Timeout :: timeout()} |
                              {ok, State :: term(), hibernate} |
                              {stop, Reason :: term()} |
                              ignore.
init([]) ->
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), term()}, State :: term()) ->
                         {reply, Reply :: term(), NewState :: term()} |
                         {reply, Reply :: term(), NewState :: term(), Timeout :: timeout()} |
                         {reply, Reply :: term(), NewState :: term(), hibernate} |
                         {noreply, NewState :: term()} |
                         {noreply, NewState :: term(), Timeout :: timeout()} |
                         {noreply, NewState :: term(), hibernate} |
                         {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
                         {stop, Reason :: term(), NewState :: term()}.
handle_call({get_middleman, Name}, _From, State = #state{middlemen = Middlemen, refs = Refs}) ->
    try maps:get(Name, Middlemen) of
        {Pid, _} ->
            {reply, {ok, Pid}, State}
    catch error:{badkey, _} ->
            {ok, Pid} = middleman_worker_sup:start_middleman(),
            Ref = erlang:monitor(process, Pid),
            {reply, {ok, Pid},
             #state{ middlemen = maps:put(Name, {Pid, Ref}, Middlemen),
                     refs = maps:put(Ref, Name, Refs)}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request :: term(), State :: term()) ->
                         {noreply, NewState :: term()} |
                         {noreply, NewState :: term(), Timeout :: timeout()} |
                         {noreply, NewState :: term(), hibernate} |
                         {stop, Reason :: term(), NewState :: term()}.
handle_cast({remove_middleman, Name}, State = #state{middlemen = Middlemen, refs = Refs}) ->
    case maps:take(Name, Middlemen) of
        {{Pid, Ref}, NewMiddlemen} ->
            erlang:demonitor(Ref),
            middleman_worker:stop(Pid),
            {noreply,
             #state{
                middlemen = NewMiddlemen,
                refs = maps:remove(Ref, Refs)}};
        error ->
            {noreply, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info :: timeout() | term(), State :: term()) ->
                         {noreply, NewState :: term()} |
                         {noreply, NewState :: term(), Timeout :: timeout()} |
                         {noreply, NewState :: term(), hibernate} |
                         {stop, Reason :: normal | term(), NewState :: term()}.
handle_info({'DOWN', Ref, _, _}, State = #state{middlemen = Middlemen, refs = Refs}) ->
    case maps:take(Ref, Refs) of
        {Name, NewRefs} ->
            {noreply, #state{ middlemen = maps:remove(Name, Middlemen),
                              refs = NewRefs}};
        error ->
            {noreply, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason :: normal | shutdown | {shutdown, term()} | term(),
                State :: term()) -> any().
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn :: term() | {down, term()},
                  State :: term(),
                  Extra :: term()) -> {ok, NewState :: term()} |
                                      {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for changing the form and appearance
%% of gen_server status when it is returned from sys:get_status/1,2
%% or when it appears in termination error logs.
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt :: normal | terminate,
                    Status :: list()) -> Status :: term().
format_status(_Opt, Status) ->
    Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
