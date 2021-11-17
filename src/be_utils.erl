-module(be_utils).

-export([pmap/2, pmap/3]).

pmap(F, L) ->
    Width = cpus(),
    pmap(F, L, Width).

pmap(F, L, Width) ->
    Parent = self(),
    Len = length(L),
    Min = floor(Len/Width),
    Rem = Len rem Width,
    Lengths = lists:duplicate(Rem, Min+1)++ lists:duplicate(Width - Rem, Min),
    OL = partition_list(L, Lengths, []),
    {St, WorkerPids} = lists:foldl(
           fun([], Acc) ->
                   Acc;
              (IL, {N, Workers}) ->
                   P = spawn_opt(
                     fun() ->
                             try lists:map(F, IL) of
                                 Res ->
                                     Parent ! {pmap, N, Res}
                             catch
                                 What:Why ->
                                     Parent ! {pmap_crash, What, Why}
                             end
                     end, [{fullsweep_after, 0}]),
                   {N+1, [P|Workers]}
           end, {0, []}, OL),
    L2 = [receive
              {pmap_crash, What, Why} ->
                  %% kill all the others
                  [ catch erlang:exit(P, normal) || P <- WorkerPids ],
                  flush_pmap_messages(),
                  erlang:What(Why);
              {pmap, N, R} -> {N,R}
          end || _ <- lists:seq(1, St)],
    {_, L3} = lists:unzip(lists:keysort(1, L2)),
    lists:flatten(L3).

flush_pmap_messages() ->
    receive
        {pmap, _N, _R} ->
            flush_pmap_messages()
    after 0 ->
              ok
    end.

partition_list([], [], Acc) ->
    lists:reverse(Acc);
partition_list(L, [0 | T], Acc) ->
    partition_list(L, T, Acc);
partition_list(L, [H | T], Acc) ->
    {Take, Rest} = lists:split(H, L),
    partition_list(Rest, T, [Take | Acc]).

cpus() ->
    Ct = erlang:system_info(schedulers_online),
    max(2, ceil(Ct/2) + 1).
