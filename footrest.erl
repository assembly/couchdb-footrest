-module(footrest).
-export([init/0]).

-record(frreq,{
    headers,
    host="localhost:5984",
    path,
    verb,
    params,
    only_include,
    order_by,
    store_as
}).
-define(JSON_ENCODE(V), mochijson2:encode(V)).
-define(JSON_DECODE(V), mochijson2:decode(V)).
-define(b2l(V), binary_to_list(V)).
-define(l2b(V), list_to_binary(V)).


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif. % TEST

%
% STARTUP EXTERNAL PROCESS LOOP
%

% Initiates Footrest.
% To be used later on for argument configuration
init() ->
    start().

% Loops over request-response cycle
start() ->
    Request = io:get_line(''),
    Response = handle_request(Request),
    io:format(Response),
    start().

%
% HANDLE REEQUEST
%

% Checks if the request is intelligible and handles it appropriately
handle_request(Request) ->
    Response = case catch parse_request(Request) of
        {invalid_json, Msg} -> {error, invalid_json, Msg};
        {error, Msg} -> {error, Msg};
        {'EXIT',{{Type,_},_}} -> {error, Type, "exit error"};
        FRequest -> {ok, handle_frequest(FRequest)}
    end,
    finalize_response(format_response(Response)).

% Extracts special parameters from request
parse_request(Request) -> 
    {Json} = ?JSON_DECODE(Request),
    HeadersSearch = lists:keysearch(<<"headers">>,1,Json),
    Headers = case HeadersSearch of
        false -> [];
        {value,{_,{HValue}}} -> HValue
    end,
    ParamsSearch = lists:keysearch(<<"query">>,1,Json),
    Params = case ParamsSearch of
        false -> [];
        {value,{_,{PValue}}} -> PValue
    end,
    #frreq{
        headers = Headers,
        host = extract_value(<<"Host">>,Headers),
        path = extract_value(<<"path">>,Json),
        verb =  extract_value(<<"verb">>,Json),
        params = figure_true_params(Params),
        only_include = extract_value(<<"only_include">>,Params),
        order_by = extract_value(<<"order_by">>,Params),
        store_as = extract_value(<<"store_as">>,Params)
    }.

handle_frequest(#frreq{}=FRequest) ->
    VerbAtom = case string:equal("POST",FRequest#frreq.verb) of
        true -> post;
        false -> get
    end,
    TruePath = figure_true_path(FRequest#frreq.path),
    Url = "http://" ++ ?b2l(FRequest#frreq.host) ++ "/" ++ TruePath,
    Params = FRequest#frreq.params,
    Response = re:replace(send_request(Url,Params,VerbAtom),"\r\n",""),
    JsonResponse = ?JSON_DECODE(Response),
    OnlyResponse = case FRequest#frreq.only_include of
        nil -> JsonResponse;
        OnlyInclude -> intersect_response(JsonResponse, ?JSON_DECODE(OnlyInclude))
    end,
    OrderedResponse = case FRequest#frreq.order_by of
        nil -> OnlyResponse;
        OrderBy -> order_response(OnlyResponse, OrderBy)
    end,
    StoredResponse = case FRequest#frreq.order_by of
        nil -> OrderedResponse;
        StoreID -> store_response(OrderedResponse, StoreID)
    end,
    ?JSON_ENCODE(StoredResponse).

%
% MODIFY DATA (WHAT YOU CAME FOR)
%

intersect_response({Response}, Keys) when is_list(Keys)->
    Rows = extract_value(<<"rows">>,Response),
    % Fold over Keys
    {_IRows, ORows} = lists:foldl(fun(El,Acc) ->
        {IRows0, ORows0} = Acc,
        % Fold over remaining input rows
        lists:foldl(fun({El1},Acc1) ->
            {IRows1, ORows1} = Acc1,
            RowKey = extract_value(<<"id">>,El1),
            case RowKey == El of
              true -> {IRows1, ORows1 ++ [{El1}]};
              false -> {IRows1 ++ [{El1}], ORows1}
            end
        end,
        {[],ORows0},
        IRows0)
    end,
    {Rows,[]},
    Keys),
    Response1 = replace_value(<<"total_rows">>,length(ORows),Response),
    {replace_value(<<"rows">>,ORows,Response1)};
% TODO: Implement
intersect_response(Response, _StoreID) ->
    Response.

order_response({Response}, OrderBy) ->
    OrderStr = ?b2l(OrderBy),
    [OrderCol, OrderDir] = case re:run(OrderStr,"^\\\[") of
        {match,_} ->
          OrderStr1 = string:substr(OrderStr,2,length(OrderStr)-2),
          re:split(OrderStr1,",");
        nomatch -> [OrderBy, <<"desc">>]
    end,
    Rows = extract_value(<<"rows">>,Response),
    ORows = lists:sort(fun({A},{B}) ->
      AValue = extract_value(OrderCol,A),
      BValue = extract_value(OrderCol,B),
      case OrderDir == <<"desc">> of
        true -> AValue >= BValue;
        false -> AValue < BValue
      end
    end,
    Rows),
    {replace_value(<<"rows">>,ORows,Response)}.

% TODO: Implement
store_response(Response, _StoreID) ->
    Response.

send_request(Url, Params, Verb) -> 
    ibrowse:start(),
    case ibrowse:send_req(Url, Params, Verb) of
        {ok,_,_,X} -> X;
        {error,Reason} -> {error,Reason}
    end.

%
% CLEAN PARAMS AND PATH
%

figure_true_params(Params) ->
    FRParamList = [{<<"only_include">>},{<<"order_by">>},{<<"store_as">>}],
    lists:foldl(fun({Key,Value},Acc) ->
        case lists:keysearch(Key,1,FRParamList) of
            {value,_} -> Acc;
            false -> [{Key,Value} | Acc]
        end
    end,
    [],
    Params).

figure_true_path(RequestPath) ->
    TruePath = remove_element(2, RequestPath),
    string_join(TruePath, "/").

%
% FINAL STUFF
%

format_response({error, Type, Msg}) ->
    {500, {}, ?l2b(atom_to_list(Type) ++ ": " ++ Msg)};
format_response({error, Msg}) ->
    {500, {}, "error" ++ ": " ++ Msg};
format_response({ok, Response}) ->
    {200, {}, ?JSON_DECODE(?l2b(Response))}.

finalize_response({Code, _Headers, Body}) ->
    BodyType = case Code of
        200 -> <<"json">>;
        500 -> <<"body">>
    end,
    ?JSON_ENCODE(
        {[
            {<<"code">>,Code},
            % {<<"headers">>,Headers},
            {BodyType,Body}
        ]}
    ) ++ "\n".


%
% UTILS
%

extract_value(Key,List) ->
    case lists:keysearch(Key,1,List) of
        false -> nil;
        {value,{_,Value}} -> Value
    end.
replace_value(Key,Value,List) ->
    lists:map(fun(El) ->
        case El of
          {Key,_} -> {Key,Value};
          Other -> Other
        end
    end,
    List).

remove_element(1, List) ->
    [_ | TheRest] = List, TheRest;
remove_element(ElemPos, List) when length(List) == ElemPos ->
    [_ | TheRest] = lists:reverse(List),
    lists:reverse(TheRest);
remove_element(ElemPos, List) ->
    {ListA, ListB} = lists:split(ElemPos - 1, List),
    [_, ElemB | ListC] = ListB,
    ListRestB = [ElemB | ListC],
    ListA ++ ListRestB.

string_join(Items, Sep) ->
    lists:flatten(lists:reverse(string_join1(Items, Sep, []))).
string_join1([Head | []], _Sep, Acc) ->
    [Head | Acc];
string_join1([Head | Tail], Sep, Acc) ->
    string_join1(Tail, Sep, [Sep, Head | Acc]).


-ifdef(TEST).

% Bad json should not crash the program but return an error.
bad_json_test() ->
    I = "{hey",
    O = <<"{\"code\":500,\"body\":\"invalid_json: {hey\"}\n">>,
    R = handle_request(I),
    %?debugMsg(R),
    ?assert(O == R).

% Simple request should proxy to database.
simple_request_test() ->
    I = "{\"headers\":{\"Host\":\"localhost:5984\"},\"verb\":\"GET\",\"path\":[\"footrest_test\",\"_footrest\",\"_all_docs\"]}",
    Oexp = "\\\"total_rows\\\\\\\":3",
    R = handle_request(I),
    %?debugMsg(R),
    {match,_} = re:run(?b2l(R), Oexp).

% Request with array of include_only keys should intersect in order.
only_include_test() ->
    I = "{\"headers\":{\"Host\":\"localhost:5984\"},\"verb\":\"GET\",\"path\":[\"footrest_test\",\"_footrest\",\"_all_docs\"],\"query\":{\"only_include\":\"[\\\"024b0d000af2e7387b20ad07f44ff06e\\\",\\\"088c36a53dc6777b014c02908a2f65f3\\\"]\"}}",
    Oexp = "\\\"total_rows\\\\\\\":2",
    R = handle_request(I),
    %?debugMsg(R),
    {match,_} = re:run(?b2l(R), Oexp).

% Request with order_by string should order by the named field desc.
order_by_test() ->
    I = "{\"headers\":{\"Host\":\"localhost:5984\"},\"verb\":\"GET\",\"path\":[\"footrest_test\",\"_footrest\",\"_all_docs\"],\"query\":{\"order_by\":\"key\"}}",
    Oexp = "\\\"total_rows\\\\\\\":3",
    R = handle_request(I),
    %?debugMsg(R),
    {match,_} = re:run(?b2l(R), Oexp). 

% Request with order_by array should order by the name and direction.
order_dir_test() ->
    I = "{\"headers\":{\"Host\":\"localhost:5984\"},\"verb\":\"GET\",\"path\":[\"footrest_test\",\"_footrest\",\"_all_docs\"],\"query\":{\"order_by\":\"[key,asc]\"}}",
    Oexp = "\\\"total_rows\\\\\\\":3",
    R = handle_request(I),
    %?debugMsg(R),
    {match,_} = re:run(?b2l(R), Oexp). 

% Request with store_as should store result in footrest caching db.

% Request with include_only string should intersect with cache.

-endif. % TEST
