-module(middleman_test).
-include_lib("eunit/include/eunit.hrl").

-define(setup(TestFun), {setup, fun start_middleman/0, fun stop_middleman/1, TestFun}).

-record(socket_pair_state, {middleman, listen_socket, sink_socket_end, sink_socket_src, port}).

%%% test descriptions
start_stop_test_() ->
    {"a middleman can be started and stopped",
     {setup, fun start_middleman/0, fun stop_middleman/1, fun is_running/1}}.

queue_data_test_() ->
    [{"middleman without a sink will accept data",
      ?setup(fun accepts_data_no_sink/1)}].

%% TODO
%% - if there are no messages held, then no data is written to the sink
%%   initially
%%
%% - if the sink is removed and a new one is set, no duplicate
%%   messages are received.
%%
%% - after the sink is removed, any new messages are held and
%%   forwarded once a new sink is set.
forward_data_test_() ->
    [{"all held messages are written to the sink in order",
      {setup,
       fun start_middleman_and_socket_pair/0,
       fun stop_middleman_and_socket_pair/1,
       fun messages_sent_in_order/1}},
     {"middleman with a sink accepts data",
      {setup,
       fun start_middleman_and_socket_pair/0,
       fun stop_middleman_and_socket_pair/1,
       fun accepts_data_with_sink/1}},
     {"middleman forwards data sent after sink is set",
      {setup,
       fun start_middleman_and_socket_pair/0,
       fun stop_middleman_and_socket_pair/1,
       fun non_held_messages_sent_in_order/1}}].

assigning_and_reassigning_test_() ->
    [{"only one sink can be set at a time",
     {setup,
      fun start_middleman_and_socket_pair/0,
      fun stop_middleman_and_socket_pair/1,
      fun cannot_assign_two_sinks/1}},
     {"if the sink is closed, it is removed and a new one can be assigned",
      {setup,
       fun start_middleman_and_socket_pair/0,
       fun stop_middleman_and_socket_pair/1,
       fun can_assign_new_sink_if_socket_closed/1}},
     {"no duplicate messages delivered if sink is closed and a new one is assigned",
      {setup,
       fun start_middleman_two_socket_pairs/0,
       fun stop_middleman_two_socket_pairs/1,
       fun no_duplicates_on_sink_error/1}}].

%%% Setup and teardown
start_middleman() ->
    {ok, Pid} = middleman_worker:start_link(),
    Pid.

stop_middleman(Pid) ->
    middleman_worker:stop(Pid).

start_middleman_and_socket_pair() ->
    {ok, LSocket} = gen_tcp:listen(0, [list, {active, false}, {packet, line}]),
    {ok, Port} = inet:port(LSocket),
    {CSocket, SinkSocket} = make_socket_pair(LSocket, Port),
    {ok, Middleman} = middleman_worker:start_link(),
    #socket_pair_state{middleman=Middleman,
                       sink_socket_end=CSocket,
                       listen_socket=LSocket,
                       sink_socket_src=SinkSocket,
                       port=Port}.

make_socket_pair(LSocket, Port) ->
    P = self(),
    spawn_link(
      fun() ->
              {ok, Socket} = gen_tcp:connect("localhost", Port,
                                             [list, {active, false}, {packet, line}]),
              gen_tcp:controlling_process(Socket, P),
              P ! {socket, Socket}
      end),
    {ok, CSocket} = gen_tcp:accept(LSocket),
    {CSocket, receive {socket, S} -> S end}.

start_middleman_two_socket_pairs() ->
    SocketPair = start_middleman_and_socket_pair(),
    Pair2 = make_socket_pair(SocketPair#socket_pair_state.listen_socket,
                             SocketPair#socket_pair_state.port),
    {SocketPair, Pair2}.

stop_middleman_two_socket_pairs({SPState, {CSocket, SSocket}}) ->
    stop_middleman_and_socket_pair(SPState),
    gen_tcp:close(CSocket),
    gen_tcp:close(SSocket).

stop_middleman_and_socket_pair(State) ->
    middleman_worker:remove_sink(State#socket_pair_state.middleman),
    gen_tcp:close(State#socket_pair_state.sink_socket_end),
    gen_tcp:close(State#socket_pair_state.sink_socket_src),
    gen_tcp:close(State#socket_pair_state.listen_socket),
    middleman_worker:stop(State#socket_pair_state.middleman).

%%% tests
is_running(Pid) ->
    ?_assert(erlang:is_process_alive(Pid)).

accepts_data_no_sink(Pid) ->
    [ ?_assertEqual(ok,
                    middleman_worker:put(
                      Pid,
                      io_lib:format("this is message ~p~n", [X])))
      || X <- lists:seq(1, 10)].

accepts_data_with_sink(#socket_pair_state{middleman=Pid, sink_socket_src=Sink}) ->
    middleman_worker:assign_sink(Pid, Sink),
    [ ?_assertEqual(ok,
                    middleman_worker:put(
                      Pid,
                      io_lib:format("this is message ~p~n", [X])))
      || X <- lists:seq(1, 10)].

messages_sent_in_order(S=#socket_pair_state{middleman=Pid, sink_socket_end=RecvSocket}) ->
    Messages = [ io_lib:format("this is message ~p~n", [N]) || N <- lists:seq(1, 10)],
    [ middleman_worker:put(Pid, M) || M <- Messages ],
    middleman_worker:assign_sink(Pid, S#socket_pair_state.sink_socket_src),
    ?_assertEqual(
       lists:map(fun lists:flatten/1, Messages),
       [ receive_line(RecvSocket) || _N <- lists:seq(1, 10)]).

non_held_messages_sent_in_order(S=#socket_pair_state{
                                     middleman=Pid,
                                     sink_socket_end=RecvSocket}) ->
    Messages = lists:map(
                 fun lists:flatten/1,
                 [io_lib:format("this is message ~p~n", [N]) || N <- lists:seq(1, 10)]),
    middleman_worker:assign_sink(Pid, S#socket_pair_state.sink_socket_src),
    [ middleman_worker:put(Pid, M) || M <- Messages ],
    ?_assertEqual(Messages, [ receive_line(RecvSocket) || _N <- lists:seq(1, 10) ]).

cannot_assign_two_sinks(S=#socket_pair_state{
                             middleman=Pid,
                             sink_socket_end=RecvSocket,
                             sink_socket_src=SinkSocket}) ->
    middleman_worker:assign_sink(Pid, SinkSocket),
    ?_assertEqual(already_assigned, middleman_worker:assign_sink(Pid, RecvSocket)).

can_remove_and_reassign_sink(S=#socket_pair_state{
                                  middleman=Pid,
                                  sink_socket_end=RecvSocket,
                                  sink_socket_src=SinkSocket}) ->
    ok = middleman_worker:assign_sink(Pid, SinkSocket),
    ok = middleman_worker:remove_sink(Pid),
    ok = middleman_worker:assign_sink(Pid, SinkSocket).

can_assign_new_sink_if_socket_closed(S=#socket_pair_state{
                                          middleman=Pid,
                                          listen_socket=LSocket,
                                          port=Port,
                                          sink_socket_end=RecvSocket,
                                          sink_socket_src=SinkSocket}) ->
    middleman_worker:assign_sink(Pid, SinkSocket),
    gen_tcp:close(SinkSocket),
    {CSocket, SSocket} = make_socket_pair(LSocket, Port),
    AssignResult = middleman_worker:assign_sink(Pid, SSocket),
    gen_tcp:close(SSocket),
    gen_tcp:close(CSocket),
    ?_assertMatch(ok, AssignResult).

no_duplicates_on_sink_error({SP=#socket_pair_state{middleman=Pid}, {CSocket, SSocket}}) ->
    middleman_worker:assign_sink(Pid, SP#socket_pair_state.sink_socket_src),
    Messages15 = [ lists:flatten(io_lib:format("this is message ~p~n", [N]))
                 || N <- lists:seq(1,5) ],
    Messages510 = [ lists:flatten(io_lib:format("this is message ~p~n", [N]))
                 || N <- lists:seq(6,10) ],
    lists:foreach(
      fun(M) ->
              middleman_worker:put(Pid, M)
      end,
      Messages15),
    Receive15 = [ receive_line(SP#socket_pair_state.sink_socket_end) || _ <- lists:seq(1, 5)],
    gen_tcp:close(SP#socket_pair_state.sink_socket_src),

    lists:foreach(
      fun(M) ->
              middleman_worker:put(Pid, M)
      end,
      Messages510),
    middleman_worker:assign_sink(Pid, SSocket),
    Receive510 = [ receive_line(CSocket) || _ <- lists:seq(1, 5)],
    ?_assertEqual(Messages15++Messages510, Receive15++Receive510).

%%% helper functions
receive_line(Socket) ->
    {ok, Message} = gen_tcp:recv(Socket, 0),
    Message.
