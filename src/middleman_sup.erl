%%%-------------------------------------------------------------------
%% @doc middleman top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(middleman_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 0,
                 period => 1},
    ChildSpecs = [#{id => middleman_worker_sup,
                    start => {middleman_worker_sup, start_link, []},
                    restart => permanent,
                    shutdown => 50000,
                    type => supervisor,
                    modules => [middleman_worker_sup]},
                  #{id => middleman_registry,
                    start => {middleman_registry, start_link, []},
                    restart => permanent,
                    shutdown => 50000,
                    type => worker,
                    modules => [middleman_registry]}],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
