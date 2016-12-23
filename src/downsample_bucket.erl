%%
%% Report bucket
%% 

-module(downsample_bucket).

-define(NO_SAMPLES, 600).

-export([
    init_metric_store/4,
    init_metric_store/5,

    insert/3
]).


-record(store, {
    stores
}).

-record(dp_store, {
    insert_query,
    samplers
}).


% @doc Initializes the history tables needed to store the samples.
init_metric_store(Name, DataPoint, Handler, HandlerState) when is_atom(DataPoint) ->
    init_metric_store(Name, [DataPoint], Handler, HandlerState);
init_metric_store(Name, DataPoints, Handler, HandlerState) ->
    init_metric_store(Name, DataPoints, [hour, day], Handler, HandlerState).

init_metric_store(Metric, DataPoints, Periods, Handler,  HandlerState) ->
    F = fun(Stg) ->
        [{DP, init_dp_store(Metric, DP, Periods, Handler, Stg)}  || DP <- DataPoints]
    end,
    DpStores = Handler:downsample_handler_transaction(F, HandlerState),
    #store{stores = DpStores}.

init_dp_store(MetricName, DataPoint, Periods, Handler, HandlerState) ->
    Samplers = [begin 
            Table = init_datapoint(MetricName, DataPoint, Period, Handler, HandlerState),
             init_sampler(Period, Table) 
         end || Period <- Periods],

    #dp_store{samplers=Samplers}.

init_datapoint(MetricName, DataPoint, Period, Handler, HandlerState) ->
    Handler:downsample_handler_init_datapoint(MetricName, DataPoint, Period, HandlerState).

init_sampler(hour, Table) ->
    largest_triangle_three_buckets:downsample_stream(6, Table);
init_sampler(day, Table) ->
    largest_triangle_three_buckets:downsample_stream(24, Table).


% @doc Insert a new sample in the store.
%
insert(#store{stores=Stores}=MS, Values, InsertDb) ->
    Now = unix_time(),
    Stores1 = [ {Dp, insert_value(Store, Now, proplists:get_value(Dp, Values), InsertDb)} || {Dp, Store} <- Stores],
    MS#store{stores=Stores1}.

insert_value(Store, _Now, undefined, _InsertDb) -> Store;
insert_value(#dp_store{samplers=Samplers}=Store, Now, Value, InsertDb) ->
    Samplers1 = insert_sample(InsertDb, Samplers, {Now, Value}, false, []),
    Store#dp_store{samplers=Samplers1}.

insert_sample(_InsertDb, [], _Point, _Ready, Acc) -> lists:reverse(Acc);
insert_sample(InsertDb, [H|T], _Point, true, Acc) -> insert_sample(InsertDb, T, _Point, true, [H|Acc]);
insert_sample(InsertDb, [H|T], Point, false, Acc) ->
    case largest_triangle_three_buckets:add(Point, H) of
        {continue, H1} -> 
            %% Done
            insert_sample(InsertDb, T, Point, true, [H1|Acc]);
        {ok, {Ts, V}=P, H1} ->
            InsertDb(largest_triangle_three_buckets:state(H1), [Ts, V]),
            insert_sample(InsertDb, T, P, false, [H1|Acc])
    end.

%%
%% Helpers
%%

unix_time() ->
    {Mega, Secs, _} = os:timestamp(),
    Mega * 1000000 + Secs.


%%
%% Helpers
%%

% heuristics for the number of seconds in a period.

%seconds(hour) -> 3600;
%seconds(day) -> seconds(hour) * 24;
%seconds(week) -> seconds(day) * 7;
%seconds(month) -> seconds(day) * 30;
%seconds(month3) -> seconds(month) * 3;
%seconds(month6) -> seconds(month) * 6;
%seconds(year) -> seconds(day) * 365.

%interval(NumberOfSamples, Period) -> 
%    seconds(Period) / NumberOfSamples.

%%
%% Tests
%%

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

%%interval_test() ->
%%    % 25920, 52560,
%%   ?assertEqual(6.0, interval(600, hour)),
%%  ?assertEqual(144.0, interval(600, day)),
%%    ?assertEqual(1008.0, interval(600, week)),
%%    ?assertEqual(4320.0, interval(600, month)),
%%    ?assertEqual(12960.0, interval(600, month3)),
%%    ?assertEqual(25920.0, interval(600, month6)),
%%    ?assertEqual(52560.0, interval(600, year)),
%%    ok.

init_metric_store_test() ->
    Handler = downsample_handler_test,
    {ok, HandlerState} = Handler:downsample_handler_init([]),

    Bucket = init_metric_store([a,b], [min, max], Handler, HandlerState),
    ok.

-endif.
