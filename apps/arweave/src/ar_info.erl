%%%
%%% @doc Gathers the data for the /info and /recent endpoints.
%%%

-module(ar_info).

-export([get_info/0, get_recent/0]).

-include_lib("arweave/include/ar.hrl").
-include_lib("arweave/include/ar_chain_stats.hrl").

get_info() ->
	{Time, Current} =
		timer:tc(fun() -> ar_node:get_current_block_hash() end),
	{Time2, Height} =
		timer:tc(fun() -> ar_node:get_height() end),
	[{_, BlockCount}] = ets:lookup(ar_header_sync, synced_blocks),
    #{
        <<"network">> => list_to_binary(?NETWORK_NAME),
        <<"version">> => ?CLIENT_VERSION,
        <<"release">> => ?RELEASE_NUMBER,
        <<"height">> =>
            case Height of
                not_joined -> -1;
                H -> H
            end,
        <<"current">> =>
            case is_atom(Current) of
                true -> atom_to_binary(Current, utf8);
                false -> ar_util:encode(Current)
            end,
        <<"blocks">> => BlockCount,
        <<"peers">> => prometheus_gauge:value(arweave_peer_count),
        <<"queue_length">> =>
            element(
                2,
                erlang:process_info(whereis(ar_node_worker), message_queue_len)
            ),
        <<"node_state_latency">> => (Time + Time2) div 2
    }.

get_recent() ->
    #{
        %% #{
        %%   "id": <indep_hash>,
        %%   "received": <received_timestamp>"
        %% }
        <<"blocks">> => get_recent_blocks(ar_node:get_height()),
        %% #{
        %%   "id": <hash_of_block_ids>,
        %%   "height": <height_of_first_orphaned_block>,
        %%   "timestamp": <timestamp_of_when_fork_was_abandoned>
        %%   "blocks": [<block_id>, <block_id>, ...]
        %% }
        <<"forks">> => get_recent_forks()
    }.

get_recent_blocks(CurrentHeight) ->
    lists:foldl(
        fun({H, _WeaveSize, _TXRoot}, Acc) ->
            Acc ++ [#{
                <<"id">> => ar_util:encode(H),
                <<"received">> => get_block_timestamp(H, length(Acc))
            }]
        end,
        [],
        lists:sublist(ar_block_index:get_list(CurrentHeight), ?CHECKPOINT_DEPTH)
    ).

get_recent_forks() ->
    lists:foldl(
        fun(Fork, Acc) ->
            #fork{ 
                id = ID, height = Height, timestamp = Timestamp, block_ids = BlockIDs} = Fork,
            Acc ++ [#{
                <<"id">> => ar_util:encode(ID),
                <<"height">> => Height,
                <<"timestamp">> => Timestamp div 1000,
                <<"blocks">> => [ ar_util:encode(BlockID) || BlockID <- BlockIDs ]
            }]
        end,
        [],
        ar_chain_stats:get_forks(0)
    ).

get_block_timestamp(H, Depth) when Depth < ?RECENT_BLOCKS_WITHOUT_TIMESTAMP ->
    <<"pending">>;
get_block_timestamp(H, _Depth) ->
    B = ar_block_cache:get(block_cache, H),
    case B#block.receive_timestamp of
        undefined -> <<"pending">>;
        Timestamp -> ar_util:timestamp_to_seconds(Timestamp)
    end.
