%%
%% TODO: Licence blurb
%% 

-module(downsample_handler).

%%
%% Types
%%

-type options() :: [{atom(), any()}].
-type handler_state() :: any().
-type datapoint_state() :: any().

-type timestamp() :: integer().
-type value() :: number().

-type transaction_fun() :: any().
-type transaction_result() :: any().

%%
%% Callbacks
%%

%%
%%
-callback(downsample_handler_init(options()) -> {ok, handler_state()}).

%%
-callback(downsample_handler_close(handler_state()) -> ok).

%%
-callback(downsample_handler_init_datapoint(
    exometer_report:metric(), 
    exometer_report:datapoint(),  
    downsample:period(), 
    handler_state()) -> datapoint_state()).

%%
-callback(downsample_handler_insert_datapoint(
    exometer_report:metric(),
    exometer_report:datapoint(),
    downsample:period(),
    timestamp(),
    value(),
    datapoint_state(), 
    handler_state()) -> any()).

%%
-callback(downsample_handler_transaction(transaction_fun(), handler_state()) -> transaction_result()).

%%
-callback(downsample_handler_get_history(
    options(),
    exometer_report:metric(),
    exometer_report:datapoint(),
    list(downsample:period())) -> any()).

%%
-callback(downsample_handler_purge(options(), handler_state()) -> ok).