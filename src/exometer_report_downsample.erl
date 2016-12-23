%%
%%
%%

-module(exometer_report_downsample).

-behaviour(exometer_report).

%% Exometer reporter callbacks
-export([
   exometer_init/1,
   exometer_info/2,
   exometer_cast/2,
   exometer_call/3,
   exometer_report/5,
   exometer_report_bulk/3,
   exometer_subscribe/5,
   exometer_unsubscribe/4,
   exometer_newentry/2,
   exometer_setopts/4,
   exometer_terminate/2
]).

-export([
    get_history/2, get_history/3
]).

-include_lib("exometer_core/include/exometer.hrl").

-record(state, {
    handler,
    handler_args,
    handler_state, 

    samplers 
}).

-type value() :: any().
-type options() :: any().
-type state() :: #state{}.
-type callback_result() ::  {ok, state()}.

-spec exometer_init(options()) -> callback_result().
exometer_init(Opts) ->
    lager:info("~p(~p): Starting", [?MODULE, Opts]),

    % We only support report bulk
    {report_bulk, true} = proplists:lookup(report_bulk, Opts),

    % Initialize the handler
    {handler, Handler} = proplists:lookup(handler, Opts),
    {handler_args, HandlerArgs} = proplists:lookup(handler_args, Opts),
    {ok, HandlerState} = Handler:downsample_handler_init(HandlerArgs),

    % Samplers.
    Samplers = dict:new(),

    {ok, #state{handler_state = HandlerState, handler=Handler, handler_args=HandlerArgs, samplers = Samplers}}.

-spec exometer_report(exometer_report:metric(), exometer_report:datapoint(), exometer_report:extra(), value(), state()) -> callback_result().
exometer_report(_Metric, _DataPoint, _Extra, _Value, State) ->
    lager:warning("~p: Use {report_bulk, true}.", [?MODULE]),
    {ok, State}.

exometer_report_bulk(Found, _Extra,  #state{handler_state = HandlerState, handler=Handler}=State) ->
    Transaction = fun(Stg) ->
        Fun = fun(Query, Args) -> Handler:downsample_handler_insert_datapoint(Query, Args, Stg) end,

        lists:foldl(fun({Metric, Values}, #state{samplers =Samplers}=S) -> 
            Samplers1 = dict:update(Metric, fun(Store) -> downsample_bucket:insert(Store, Values, Fun) end, Samplers),
            S#state{samplers=Samplers1}
        end, State, Found)
    end,

    State1 = case Handler:downsample_handler_transaction(Transaction, HandlerState) of
        {rollback, _}=R -> throw(R);
        S -> S
    end,

    {ok, State1}.

-spec exometer_subscribe(exometer_report:metric(), exometer_report:datapoint(), exometer_report:interval(), exometer_report:extra(), state()) -> callback_result().
exometer_subscribe(Metric, DataPoint, _Interval, _SubscribeOpts,  #state{handler_state = HandlerState, handler=Handler, samplers=Samplers}=State) ->
    Store = downsample_bucket:init_metric_store(Metric, DataPoint, Handler, HandlerState),
    {ok, State#state{samplers=dict:store(Metric, Store, Samplers)}}.

-spec exometer_unsubscribe(exometer_report:metric(), exometer_report:datapoint(), exometer_report:extra(), state()) -> callback_result().
exometer_unsubscribe(Metric, _DataPoint, _Extra, #state{samplers=Samplers}=State) ->
    %% Remove the entry of this metric.
    {ok, State#state{samplers=dict:erase(Metric, Samplers)}}.

-spec exometer_call(any(), pid(), state()) -> {reply, any(), state()} | {noreply, state()} | any().
exometer_call(_Unknown, _From, State) ->
    {ok, State}.

-spec exometer_cast(any(), state()) -> {noreply, state()} | any().
exometer_cast(_Unknown, State) ->
    {ok, State}.

-spec exometer_info(any(), state()) -> callback_result().
exometer_info(_Unknown, State) ->
    {ok, State}.

-spec exometer_newentry(exometer:entry(), state()) -> callback_result().
exometer_newentry(_Entry,  State) ->
    {ok, State}.

-spec exometer_setopts(exometer:entry(), options(), exometer:status(), state()) -> callback_result().
exometer_setopts(_Metric, _Options, _Status, State) ->
    {ok, State}.

-spec exometer_terminate(any(), state()) -> any().
exometer_terminate(Reason, #state{handler=Handler, handler_state=HandlerState}) ->
    lager:info("~p(~p): Terminating", [?MODULE, Reason]),
    ok = Handler:downsample_handler_close(HandlerState).


%%
%% Extra API, TODO, move
%%

-spec get_history(exometer:metric(), exometer_report:datapoint(), any())  -> list().
get_history(Metric, DataPoint) ->
    %% TODO: fix hard code db name. 
    {ok, Conn} = esqlite3:open("priv/log/metrics.db"),
    Result = get_history(Metric, DataPoint, Conn),
    esqlite3:close(Conn),
    Result.

get_history(Metric, DataPoint, Db) when is_atom(DataPoint) -> get_history(Metric, [DataPoint], Db);
get_history(Metric, DataPoint, Db) ->
    F = fun(TDb) -> get_history(Metric, DataPoint, [hour, day], TDb, []) end,
    esqlite3_utils:transaction(F, Db).

% @doc Get the historic values of a datapoint
get_history(_Metric, [], _Periods, _Db, Acc) -> lists:reverse(Acc);
get_history(Metric, [Point|Rest], Periods, Db, Acc) ->
    DataPoints = [sqlite_report_bucket:get_history(Metric, Point, Period, Db) || Period <- Periods],
    Stats = lists:zip(Periods, DataPoints),
    get_history(Metric, Rest, Periods, Db, [{{Metric, Point}, Stats} | Acc]).
   