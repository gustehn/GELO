-module(gelo_translator).

-export([start/2]).
-record(info, {exports = []}).

start(Mod, S) ->
    Info = #info{},
    %S.
    {NewInfo, Trans} = do_translate(S, [], Info),
    %Trans.
    make_forms(Mod, Trans, NewInfo).
do_translate([], Trans, Info) ->
    {Info, Trans};
do_translate([{function, Name, [], Fun}|T], Trans, Info) ->
    Exports = Info#info.exports,
    NewInfo = Info#info{exports = [{list_to_atom(Name), 0}|Exports]},
    do_translate(T, [{function, 1, list_to_atom(Name), 0, [{clause, 1, [], [], do_fun(Fun)}]}|Trans], NewInfo);

do_translate([{function, Name, Vars, Fun}|T], Trans, Info) ->
    Exports = Info#info.exports,
    NewInfo = Info#info{exports = [{list_to_atom(Name), length(Vars)}|Exports]},
    do_translate(T, [{function, 1, list_to_atom(Name), length(Vars), [{clause, 1, do_fun(Vars), [], do_fun(Fun)}]}|Trans], NewInfo).

do_fun([]) ->
    [];
do_fun([H|T]) ->
    [do_fun(H)|do_fun(T)];
do_fun({atom, Atom}) ->
    {atom, 1, list_to_atom(Atom)};
do_fun({variable, Var}) ->
    {var, 1, list_to_atom(Var)};
do_fun({assign, Arg1, Arg2}) ->
    {match, 1, do_fun(Arg1), do_fun(Arg2)};
do_fun({call, Arg1, Arg2}) ->
    {call, 1, {atom, 1, list_to_atom(Arg1)}, do_fun(Arg2)};
do_fun({ifs, Arg1, Arg3}) ->
    {'if', 1, [lists:merge([{clause, 1, [], [lists:flatten(do_fun(Arg1))], do_fun(Arg3)}])]};
do_fun({ifs, Arg1, Arg2, Arg3}) ->
    {'if', 1, lists:flatten([{clause, 1, [], [lists:flatten(do_fun(Arg1))], do_fun(Arg2)}, do_fun(Arg3)])};
do_fun({Arg1, 'and', Arg2}) ->
    [do_fun(Arg1), do_fun(Arg2)];
do_fun({else, [], Arg1}) ->
    {clause, 1, [],[[{atom, 1, true}]], do_fun(Arg1)};
do_fun({elseif, Arg1, Arg2}) ->
    {clause, 1, [], [lists:flatten(do_fun(Arg1))], do_fun(Arg2)};
do_fun({echo, Arg1}) ->
    {call, 1, {remote, 1, {atom, 1, io}, {atom, 1, format}}, [{string, 1, "~p~n"}, {cons, 1, do_fun(Arg1), {nil, 1}}]};
do_fun({ext, {name, _, Mod}, {name, _, Fun}, Args}) ->
    {call, 1, {remote, 1, {atom, 1, list_to_atom(Mod)}, {atom, 1, list_to_atom(Fun)}}, do_fun(Args)};
do_fun({spawn, Arg1}) ->
    do_spawn(Arg1);
do_fun({gt, Arg1, Arg2}) ->
    {op, 1, '>', do_fun(Arg1), do_fun(Arg2)};
do_fun({lt, Arg1, Arg2}) ->
    {op, 1, '<', do_fun(Arg1), do_fun(Arg2)};
do_fun({leq, Arg1, Arg2}) ->
    {op, 1, '=<', do_fun(Arg1), do_fun(Arg2)};
do_fun({geq, Arg1, Arg2}) ->
    {op, 1, '>=', do_fun(Arg1), do_fun(Arg2)};
do_fun({neq, Arg1, Arg2}) ->
    {op, 1, '/=', do_fun(Arg1), do_fun(Arg2)};
do_fun({eq, Arg1, Arg2}) ->
    {op, 1, '=:=', do_fun(Arg1), do_fun(Arg2)};
do_fun({subtract, Arg1, Arg2}) ->
    {op, 1, '-', do_fun(Arg1), do_fun(Arg2)};
do_fun({add, Arg1, Arg2}) ->
    {op, 1, '+', do_fun(Arg1), do_fun(Arg2)};
do_fun({string, concat, Arg1, Arg2}) ->
    {op, 1, '++', do_fun(Arg1), do_fun(Arg2)};
do_fun({multiply, Arg1, Arg2}) ->
    {op, 1, '*', do_fun(Arg1), do_fun(Arg2)};
do_fun({divide, Arg1, Arg2}) ->
    {op, 1, '/', do_fun(Arg1), do_fun(Arg2)};
do_fun({string, Arg1}) ->
    [S] = string:tokens(Arg1, "\""),
    {string, 1, S};
do_fun({list, Arg1}) ->
    do_list(Arg1);
do_fun({string, 1, Arg1}) ->
    [S] = string:tokens(Arg1, "\""),
    {string, 1, S};
do_fun({get, List, Index}) ->
    {call, 1, {remote, 1, {atom, 1, gelo_lib}, {atom, 1, get_value}}, [do_fun(List), do_fun(Index), {integer, 1, 0}]};
do_fun({bang, Arg1, Arg2}) ->
    {op, 1, '!', do_fun(Arg1), do_fun(Arg2)};
do_fun({recv, Arg}) ->
    {'receive', 1, do_fun(Arg)};
do_fun({recvopt, Arg1, Arg2}) ->
    {clause, 1, [do_fun(Arg1)], [], do_fun(Arg2)};
do_fun({tuple, Arg}) ->
    {tuple, 1, do_fun(Arg)};
do_fun({integer, N}) ->
    {integer,1,N}.
do_list([]) ->
    {nil, 1};
do_list([H|T]) ->
    {cons, 1, do_fun(H), do_list(T)}.

do_spawn([]) ->
    [];
do_spawn([H|_T]) ->
    {call, 1, {atom, 1, spawn}, [{'fun', 1, {clauses, [{clause, 1, [], [], [do_fun(H)]}]}}]}.


make_forms(Mod, Trans, Info) ->
    {ok, Name, Beam} = compile:forms([{attribute,1,module,Mod}, {attribute, 1, export, Info#info.exports}|Trans]),
    FileName = atom_to_list(Name) ++ ".beam",
    file:write_file(FileName, Beam),
    c:l(Name),
    {ok, Name}.
