-module(middleman_registry_tests).
-include_lib("eunit/include/eunit.hrl").

%%% Desiderata
%%%
%%% - The registry can be started/stopped and is registered under the
%%%   name 'middleman_registry'
%%% - A new middleman is created when one is requested under an
%%%   unregistered name.
%%% - the same middleman is returned for repeated get calls
%%% - A middleman can be removed and recreated, resulting in a
%%%   different PID for the new middleman.

%%========================================================================
%% Test descriptions
%%========================================================================

%% Basically the same as the example from "Learn You Some Erlang"
start_stop_test_() ->
    {"the registry can be started, stopped, and has a registered name",
     {setup,
      fun start/0,
      fun stop/1,
      fun is_registered/1
     }}.

get_test_() ->
    [
     {"a new middleman is created if it does not already exist",
      {setup, fun start_app/0, fun stop_app/1, fun create_on_get/0}},
     {"the same middleman process is returned for repeated gets",
      {setup, fun start_with_one_middleman/0, fun stop_app/1, fun create_only_once/1}},
     {"multiple meddlemen can be created with different names",
      {setup, fun start_with_one_middleman/0, fun stop_app/1, fun create_multiple/1}}
    ].

remove_test_() ->
    [{"middleman stopps when removed from the registry",
      {setup, fun start_with_one_middleman/0, fun stop_app/1, fun stop_middleman/1}},
     {"middlemen can be removed and recreated",
      {setup, fun start_with_one_middleman/0, fun stop_app/1, fun remove_and_recreate/1}}].

%%========================================================================
%% Setup and teardown functions
%%========================================================================
start() ->
    {ok, Pid} = middleman_registry:start_link(),
    Pid.

stop(Pid) ->
    gen_server:stop(Pid).

start_app() ->
    ok = application:start(middleman).

stop_app(_) ->
    ok = application:stop(middleman).

start_with_one_middleman() ->
    application:start(middleman),
    {ok, Pid} = middleman_registry:get("m1"),
    {"m1", Pid}.

%%========================================================================
%% Tests
%%========================================================================
is_registered(Pid) ->
    [?_assert(erlang:is_process_alive(Pid)),
     ?_assertEqual(Pid, whereis('middleman_registry'))].

create_on_get() ->
    {ok, Pid} = middleman_registry:get("m1"),
    ?assert(erlang:is_process_alive(Pid)).

create_only_once({Name, Pid}) ->
    ?_assertEqual(Pid, element(2, middleman_registry:get(Name))).

create_multiple({Name, Pid}) ->
    [?_assertNotEqual(Pid, element(2, middleman_registry:get("m2"))),
     ?_assert(erlang:is_process_alive(Pid)),
     ?_assertEqual(Pid, element(2, middleman_registry:get(Name)))].

remove_and_recreate({Name, Pid}) ->
    ?_assertNotEqual(Pid, begin middleman_registry:remove(Name), middleman_registry:get(Name) end).

stop_middleman({Name, Pid}) ->
    middleman_registry:remove(Name),
    timer:sleep(20),
    ?_assert(not erlang:is_process_alive(Pid)).
