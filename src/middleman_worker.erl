%%%-------------------------------------------------------------------
%%% @author Will Vining <wfvining@gmail.com>
%%% @copyright (C) 2019, Will Vining
%%% @doc
%%%
%%% @end
%%% Created : 15 Sep 2019 by Will Vining <wfvining@gmail.com>
%%%-------------------------------------------------------------------
-module(middleman_worker).

-behaviour(gen_server).

%% API
-export([start_link/0, assign_sink/2, remove_sink/1, put/2, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-record(state, {sink = undefined,
                held_messages = queue:new()}).

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
    gen_server:start_link(?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Assign a socket as the sink for the middleman server
%% @end
%%--------------------------------------------------------------------
-spec assign_sink(Middleman :: pid(), Sink :: gen_tcp:socket()) -> ok | already_assigned.
assign_sink(Middleman, Sink) ->
    gen_server:call(Middleman, {assign_sink, Sink}).

%%--------------------------------------------------------------------
%% @doc
%% Remove the assigned sink
%% @end
%%--------------------------------------------------------------------
-spec remove_sink(Middleman :: pid()) -> ok.
remove_sink(Middleman) ->
    gen_server:cast(Middleman, remove_sink).

%%--------------------------------------------------------------------
%% @doc
%% Stop the middleman. Discards any held messages.
%%--------------------------------------------------------------------
-spec stop(Middleman :: pid()) -> ok.
stop(Middleman) ->
    gen_server:stop(Middleman).

%%--------------------------------------------------------------------
%% @doc
%% Pass a message to the middleman. The message will be held and
%% forwarded if/when a sink is assigned.
%% @end
%% --------------------------------------------------------------------
-spec put(Middleman :: pid(), Message :: term()) -> ok.
put(Middleman, Message) ->
    gen_server:cast(Middleman, {put_message, Message}).

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
handle_call({assign_sink, Sink}, _From, State = #state{ sink = undefined }) ->
    %% use a timeout to start writing messages to the sink when there
    %% is no other work to do.
    self() ! drain_messages,
    {reply, ok, State#state{sink = Sink}};
handle_call({assign_sink, NewSink}, _From, State = #state{ sink = SinkSocket }) ->
    %% XXX: I can't find a better way to test if the socket is closed.
    %%      The inet man page says the the behavior I rely on here is
    %%      for backward compatability, which would imply that this is
    %%      not the right way to do this.
    case inet:getopts(SinkSocket, [mode]) of
        {ok, _} ->
            {reply, already_assigned, State};
        {error, _} ->
            self() ! drain_messages,
            {reply, ok, State#state{sink = NewSink}}
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
handle_cast({put_message, Message}, State = #state{held_messages = Q}) ->
    case queue:is_empty(Q) of
        true  -> self() ! drain_messages;
        false -> ok
    end,
    {noreply, State#state{held_messages = queue:in(Message, Q)}};
handle_cast(remove_sink, State) ->
    {noreply, State#state{sink = undefined}}.

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
handle_info(drain_messages, State = #state{sink = undefined}) ->
    {noreply, State};
handle_info(drain_messages, State = #state{held_messages = Q, sink = Sink}) ->
    case queue:out(Q) of
        {{value, Message}, NewQ} ->
            case gen_tcp:send(Sink, Message) of
                ok ->
                    self() ! drain_messages,
                    {noreply, State#state{held_messages = NewQ}};
                {error, _Reason} ->
                    %% the connection broke. remove the sink and keep
                    %% Message in the queue.
                    {noreply, State#state{held_messages = Q, sink = undefined}}
            end;
        {empty, _} ->
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
