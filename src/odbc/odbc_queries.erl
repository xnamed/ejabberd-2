%%%----------------------------------------------------------------------
%%% File    : odbc_queries.erl
%%% Author  : Mickael Remond <mremond@process-one.net>
%%% Purpose : ODBC queries dependind on back-end
%%% Created : by Mickael Remond <mremond@process-one.net>
%%%
%%%
%%% ejabberd, Copyright (C) 2002-2013   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA
%%%
%%%----------------------------------------------------------------------

-module(odbc_queries).
-author("mremond@process-one.net").

-export([
         update_t/4,
	 sql_transaction/2,
	 get_last/2,
	 set_last_t/4,
	 del_last/2,
	 get_password/2,
	 get_user/2,
	 set_password_t/3,
	 add_user/4,
	 del_user/2,
	 del_user_return_password/3,
	 list_users/1,
         list_users/2,
	 users_number/1,
         users_number/2,
	 add_spool_sql/2,
	 add_spool/2,
	 get_and_del_spool_msg_t/2,
	 del_spool_msg/2,
	 get_roster/2,
	 get_roster_jid_groups/2,
	 get_roster_groups/3,
	 del_user_roster_t/2,
	 get_roster_by_jid/3,
	 get_rostergroup_by_jid/3,
	 del_roster/3,
	 del_roster_sql/2,
	 update_roster/5,
	 update_roster_sql/4,
	 roster_subscribe/4,
	 get_subscription/3,
	 set_private_data/4,
	 set_private_data_sql/3,
	 get_private_data/3,
	 del_user_private_storage/2,
	 get_default_privacy_list/2,
	 get_default_privacy_list_t/1,
	 get_privacy_list_names/2,
	 get_privacy_list_names_t/1,
	 get_privacy_list_id/3,
	 get_privacy_list_id_t/2,
	 get_privacy_list_data/3,
	 get_privacy_list_data_by_id/2,
         get_privacy_list_data_by_id_t/1,
	 set_default_privacy_list/2,
	 unset_default_privacy_list/2,
	 remove_privacy_list/2,
	 add_privacy_list/2,
	 set_privacy_list/2,
	 del_privacy_lists/3,
	 set_vcard/26,
	 get_vcard/2,
	 escape/1,
	 set_failure_time/3,
	 get_failure_time/2,
	 add_security_log/7,
	 count_records_where/3,
	 get_roster_version/2,
	 set_roster_version/2]).

-include("ejabberd.hrl").

-define(PASSWORD_ENCRYPTION_KEY(LServer),
	"SHA2('" ++ ejabberd_odbc:escape(ejabberd_config:get_local_option({odbc_encryption_key, LServer})) ++ "', 512)").

%% Almost a copy of string:join/2.
%% We use this version because string:join/2 is relatively
%% new function (introduced in R12B-0).
join([], _Sep) ->
    [];
join([H|T], Sep) ->
    [H, [[Sep, X] || X <- T]].

%% Safe atomic update.
update_t(Table, Fields, Vals, Where) ->
    UPairs = lists:zipwith(fun(A, B) -> A ++ "='" ++ B ++ "'" end,
			   Fields, Vals),
    case ejabberd_odbc:sql_query_t(
	   ["update ", Table, " set ",
	    join(UPairs, ", "),
	    " where ", Where, ";"]) of
	{updated, 1} ->
	    ok;
	_ ->
	    ejabberd_odbc:sql_query_t(
	      ["insert into ", Table, "(", join(Fields, ", "),
	       ") values ('", join(Vals, "', '"), "');"])
    end.

update_t_noesc(Table, Fields, Vals, Where) ->
    UPairs = lists:zipwith(fun(A, B) -> A ++ "=" ++ B end,
			   Fields, Vals),
    case ejabberd_odbc:sql_query_t(
	   ["update ", Table, " set ",
	    join(UPairs, ", "),
	    " where ", Where, ";"]) of
	{updated, 1} ->
	    ok;
	_ ->
	    ejabberd_odbc:sql_query_t(
	      ["insert into ", Table, "(", join(Fields, ", "),
	       ") values (", join(Vals, ", "), ");"])
    end.

update(LServer, Table, Fields, Vals, Where) ->
    UPairs = lists:zipwith(fun(A, B) -> A ++ "='" ++ B ++ "'" end,
			   Fields, Vals),
    case ejabberd_odbc:sql_query(
	   LServer,
	   ["update ", Table, " set ",
	    join(UPairs, ", "),
	    " where ", Where, ";"]) of
	{updated, 1} ->
	    ok;
	_ ->
	    ejabberd_odbc:sql_query(
	      LServer,
	      ["insert into ", Table, "(", join(Fields, ", "),
	       ") values ('", join(Vals, "', '"), "');"])
    end.

%% F can be either a fun or a list of queries
%% TODO: We should probably move the list of queries transaction
%% wrapper from the ejabberd_odbc module to this one (odbc_queries)
sql_transaction(LServer, F) ->
    ejabberd_odbc:sql_transaction(LServer, F).

get_last(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select seconds, state from last "
       "where username='", Username, "'"]).

set_last_t(LServer, Username, Seconds, State) ->
    update(LServer, "last", ["username", "seconds", "state"],
	   [Username, Seconds, State],
	   ["username='", Username, "'"]).

del_last(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from last where username='", Username, "'"]).

get_password(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select AES_DECRYPT(UNHEX(password), " ?PASSWORD_ENCRYPTION_KEY(LServer) ") AS password from users "
       "where username='", Username, "';"]).

get_user(LServer, Username) ->
	ejabberd_odbc:sql_query(
	  LServer,
	  ["select 1 from users where username='", Username, "';"]).

get_failure_time(LServer, Username) ->
	ejabberd_odbc:sql_query(
	  LServer,
	  ["SELECT last_login_failure FROM users WHERE username='", Username, "';"]).

set_failure_time(LServer, Username, Time) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["UPDATE users SET last_login_failure = ", lists:flatten(io_lib:format("~p", [Time])),
       " WHERE username = '", Username, "';"]).

set_password_t(LServer, Username, Pass) ->
    ejabberd_odbc:sql_transaction(
      LServer,
      fun() ->
	      update_t_noesc("users", ["username", "password"],
		    ["'" ++ Username ++ "'", "HEX(AES_ENCRYPT('" ++ Pass ++ "', " ?PASSWORD_ENCRYPTION_KEY(LServer) "))"],
		       ["username='", Username ,"'"])
      end).

add_user(LServer, Username, Pass, Source) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["insert into users(username, password, source) "
      	"values ('", Username, "', HEX(AES_ENCRYPT('", Pass, "', " ?PASSWORD_ENCRYPTION_KEY(LServer) ")), '", Source, "');"]).

del_user(LServer, Username) ->
    LockedPassword = string:concat("locked ", lists:flatten(io_lib:format("~p", [erlang:localtime()]))),
    LockedPasswordRandomized = string:concat(LockedPassword, get_random_string(15, "0123456789ABCDEF")),
    set_password_t(LServer, Username, LockedPasswordRandomized).

get_random_string(Length, AllowedChars) ->
    lists:foldl(fun(_, Acc) ->
                [lists:nth(random:uniform(length(AllowedChars)),
                        AllowedChars)]
                ++ Acc
        end, [], lists:seq(1, Length)).

del_user_return_password(LServer, Username, Pass) ->
    P = ejabberd_odbc:sql_query_t(
	  	["select AES_DECRYPT(UNHEX(password), " ?PASSWORD_ENCRYPTION_KEY(LServer) ") AS password from users where username='",
	   Username, "';"]),
    ejabberd_odbc:sql_query_t(["delete from users "
			"where username='", Username, "' and password = HEX(AES_ENCRYPT('", Pass, "', " ?PASSWORD_ENCRYPTION_KEY(LServer), "));"]),
    P.

list_users(LServer) ->
    ejabberd_odbc:sql_query(
      LServer,
      "select username from users").

list_users(LServer, [{from, Start}, {to, End}]) when is_integer(Start) and
                                                     is_integer(End) ->
    list_users(LServer, [{limit, End-Start+1}, {offset, Start-1}]);
list_users(LServer, [{prefix, Prefix}, {from, Start}, {to, End}]) when is_list(Prefix) and
                                                                       is_integer(Start) and
                                                                       is_integer(End) ->
    list_users(LServer, [{prefix, Prefix}, {limit, End-Start+1}, {offset, Start-1}]);

list_users(LServer, [{limit, Limit}, {offset, Offset}]) when is_integer(Limit) and
                                                             is_integer(Offset) ->
    ejabberd_odbc:sql_query(
      LServer,
      io_lib:format(
        "select username from users " ++
        "order by username " ++
        "limit ~w offset ~w", [Limit, Offset]));
list_users(LServer, [{prefix, Prefix},
                     {limit, Limit},
                     {offset, Offset}]) when is_list(Prefix) and
                                             is_integer(Limit) and
                                             is_integer(Offset) ->
    ejabberd_odbc:sql_query(
      LServer,
      io_lib:format("select username from users " ++
                    "where username like '~s%' " ++
                    "order by username " ++
                    "limit ~w offset ~w ", [Prefix, Limit, Offset])).

users_number(LServer) ->
    case element(1, ejabberd_config:get_local_option({odbc_server, LServer})) of
    pgsql ->
	case ejabberd_config:get_local_option({pgsql_users_number_estimate, LServer}) of
	true ->
	    ejabberd_odbc:sql_query(
	    LServer,
	    "select reltuples from pg_class where oid = 'users'::regclass::oid");
	_ ->
	    ejabberd_odbc:sql_query(
	    LServer,
	    "select count(*) from users")
        end;
    _ ->
	ejabberd_odbc:sql_query(
	LServer,
	"select count(*) from users")
    end.

users_number(LServer, [{prefix, Prefix}]) when is_list(Prefix) ->
    ejabberd_odbc:sql_query(
      LServer,
      io_lib:fwrite("select count(*) from users " ++
                    %% Warning: Escape prefix at higher level to prevent SQL
                    %%          injection.
                    "where username like '~s%'", [Prefix]));
users_number(LServer, []) ->
    users_number(LServer).


add_spool_sql(Username, XML) ->
    ["insert into spool(username, xml) "
     "values ('", Username, "', '",
     XML,
     "');"].

add_spool(LServer, Queries) ->
    ejabberd_odbc:sql_transaction(
      LServer, Queries).

get_and_del_spool_msg_t(LServer, Username) ->
    F = fun() ->
		Result = ejabberd_odbc:sql_query_t(
			   ["select username, xml from spool where username='", Username, "'"
			    "  order by seq;"]),
		ejabberd_odbc:sql_query_t(
		  ["delete from spool where username='", Username, "';"]),
		Result
	end,
    ejabberd_odbc:sql_transaction(LServer,F).

del_spool_msg(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from spool where username='", Username, "';"]).

get_roster(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select username, jid, nick, subscription, ask, "
       "askmessage, server, subscribe, type from rosterusers "
       "where username='", Username, "'"]).

get_roster_jid_groups(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select jid, grp from rostergroups "
       "where username='", Username, "'"]).

get_roster_groups(_LServer, Username, SJID) ->
    ejabberd_odbc:sql_query_t(
      ["select grp from rostergroups "
       "where username='", Username, "' "
       "and jid='", SJID, "';"]).

del_user_roster_t(LServer, Username) ->
    ejabberd_odbc:sql_transaction(
      LServer,
      fun() ->
	      ejabberd_odbc:sql_query_t(
		["delete from rosterusers "
		 "      where username='", Username, "';"]),
	      ejabberd_odbc:sql_query_t(
		["delete from rostergroups "
		 "      where username='", Username, "';"])
      end).

get_roster_by_jid(_LServer, Username, SJID) ->
    ejabberd_odbc:sql_query_t(
    ["select username, jid, nick, subscription, "
     "ask, askmessage, server, subscribe, type from rosterusers "
     "where username='", Username, "' "
     "and jid='", SJID, "';"]).

get_rostergroup_by_jid(LServer, Username, SJID) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select grp from rostergroups "
       "where username='", Username, "' "
       "and jid='", SJID, "'"]).

del_roster(_LServer, Username, SJID) ->
    ejabberd_odbc:sql_query_t(
      ["delete from rosterusers "
       "      where username='", Username, "' "
       "        and jid='", SJID, "';"]),
    ejabberd_odbc:sql_query_t(
      ["delete from rostergroups "
       "      where username='", Username, "' "
       "        and jid='", SJID, "';"]).

del_roster_sql(Username, SJID) ->
    [["delete from rosterusers "
      "      where username='", Username, "' "
      "        and jid='", SJID, "';"],
     ["delete from rostergroups "
      "      where username='", Username, "' "
      "        and jid='", SJID, "';"]].

update_roster(_LServer, Username, SJID, ItemVals, ItemGroups) ->
    update_t("rosterusers",
	     ["username", "jid", "nick", "subscription", "ask",
	      "askmessage", "server", "subscribe", "type"],
	     ItemVals,
	     ["username='", Username, "' and jid='", SJID, "'"]),
    ejabberd_odbc:sql_query_t(
      ["delete from rostergroups "
       "      where username='", Username, "' "
       "        and jid='", SJID, "';"]),
    lists:foreach(fun(ItemGroup) ->
			  ejabberd_odbc:sql_query_t(
			    ["insert into rostergroups("
			     "              username, jid, grp) "
			     " values ('", join(ItemGroup, "', '"), "');"])
		  end,
		  ItemGroups).

update_roster_sql(Username, SJID, ItemVals, ItemGroups) ->
    [["delete from rosterusers "
      "      where username='", Username, "' "
      "        and jid='", SJID, "';"],
     ["insert into rosterusers("
      "              username, jid, nick, "
      "              subscription, ask, askmessage, "
      "              server, subscribe, type) "
      " values ('", join(ItemVals, "', '"), "');"],
     ["delete from rostergroups "
      "      where username='", Username, "' "
      "        and jid='", SJID, "';"]] ++
     [["insert into rostergroups("
       "              username, jid, grp) "
       " values ('", join(ItemGroup, "', '"), "');"] ||
	 ItemGroup <- ItemGroups].

roster_subscribe(_LServer, Username, SJID, ItemVals) ->
    update_t("rosterusers",
	     ["username", "jid", "nick", "subscription", "ask",
	      "askmessage", "server", "subscribe", "type"],
	     ItemVals,
	     ["username='", Username, "' and jid='", SJID, "'"]).

get_subscription(LServer, Username, SJID) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select subscription from rosterusers "
       "where username='", Username, "' "
       "and jid='", SJID, "'"]).

set_private_data(_LServer, Username, LXMLNS, SData) ->
    update_t("private_storage",
	     ["username", "namespace", "data"],
	     [Username, LXMLNS, SData], 
	     ["username='", Username, "' and namespace='", LXMLNS, "'"]).

set_private_data_sql(Username, LXMLNS, SData) ->
    [["delete from private_storage "
       "where username='", Username, "' and "
       "namespace='", LXMLNS, "';"],
      ["insert into private_storage(username, namespace, data) "
       "values ('", Username, "', '", LXMLNS, "', "
       "'", SData, "');"]].

get_private_data(LServer, Username, LXMLNS) ->
    ejabberd_odbc:sql_query(
		 LServer,
		 ["select data from private_storage "
		  "where username='", Username, "' and "
		  "namespace='", LXMLNS, "';"]).

del_user_private_storage(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from private_storage where username='", Username, "';"]).

set_vcard(LServer, LUsername, SBDay, SCTRY, SEMail, SFN, SFamily, SGiven,
	  SLBDay, SLCTRY, SLEMail, SLFN, SLFamily, SLGiven, SLLocality,
	  SLMiddle, SLNickname, SLOrgName, SLOrgUnit, SLocality, SMiddle,
	  SNickname, SOrgName, SOrgUnit, SVCARD, Username) ->
    ejabberd_odbc:sql_transaction(
      LServer,
      fun() ->
	      update_t("vcard", ["username", "vcard"],
		       [LUsername, SVCARD],
		       ["username='", LUsername, "'"]),
	      update_t("vcard_search",
		       ["username", "lusername", "fn", "lfn", "family",
			"lfamily", "given", "lgiven", "middle", "lmiddle",
			"nickname", "lnickname", "bday", "lbday", "ctry",
			"lctry", "locality", "llocality", "email", "lemail",
			"orgname", "lorgname", "orgunit", "lorgunit"],
		       [Username, LUsername, SFN, SLFN, SFamily, SLFamily,
			SGiven, SLGiven, SMiddle, SLMiddle, SNickname,
			SLNickname, SBDay, SLBDay, SCTRY, SLCTRY,
			SLocality, SLLocality, SEMail, SLEMail, SOrgName,
			SLOrgName, SOrgUnit, SLOrgUnit],
		       ["lusername='", LUsername, "'"])
      end).

get_vcard(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select vcard from vcard "
       "where username='", Username, "';"]).

get_default_privacy_list(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select name from privacy_default_list "
       "where username='", Username, "';"]).

get_default_privacy_list_t(Username) ->
    ejabberd_odbc:sql_query_t(
      ["select name from privacy_default_list "
       "where username='", Username, "';"]).

get_privacy_list_names(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select name from privacy_list "
       "where username='", Username, "';"]).

get_privacy_list_names_t(Username) ->
    ejabberd_odbc:sql_query_t(
      ["select name from privacy_list "
       "where username='", Username, "';"]).

get_privacy_list_id(LServer, Username, SName) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select id from privacy_list "
       "where username='", Username, "' and name='", SName, "';"]).

get_privacy_list_id_t(Username, SName) ->
    ejabberd_odbc:sql_query_t(
      ["select id from privacy_list "
       "where username='", Username, "' and name='", SName, "';"]).

get_privacy_list_data(LServer, Username, SName) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select t, value, action, ord, match_all, match_iq, "
       "match_message, match_presence_in, match_presence_out "
       "from privacy_list_data "
       "where id = (select id from privacy_list where "
       "            username='", Username, "' and name='", SName, "') "
       "order by ord;"]).

get_privacy_list_data_by_id(LServer, ID) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select t, value, action, ord, match_all, match_iq, "
       "match_message, match_presence_in, match_presence_out "
       "from privacy_list_data "
       "where id='", ID, "' order by ord;"]).

get_privacy_list_data_by_id_t(ID) ->
    ejabberd_odbc:sql_query_t(
      ["select t, value, action, ord, match_all, match_iq, "
       "match_message, match_presence_in, match_presence_out "
       "from privacy_list_data "
       "where id='", ID, "' order by ord;"]).

set_default_privacy_list(Username, SName) ->
    update_t("privacy_default_list", ["username", "name"],
	     [Username, SName], ["username='", Username, "'"]).

unset_default_privacy_list(LServer, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from privacy_default_list "
       "      where username='", Username, "';"]).

remove_privacy_list(Username, SName) ->
    ejabberd_odbc:sql_query_t(
      ["delete from privacy_list "
       "where username='", Username, "' and name='", SName, "';"]).

add_privacy_list(Username, SName) ->
    ejabberd_odbc:sql_query_t(
      ["insert into privacy_list(username, name) "
       "values ('", Username, "', '", SName, "');"]).

set_privacy_list(ID, RItems) ->
    ejabberd_odbc:sql_query_t(
      ["delete from privacy_list_data "
       "where id='", ID, "';"]),
    lists:foreach(fun(Items) ->
			  ejabberd_odbc:sql_query_t(
			    ["insert into privacy_list_data("
			     "id, t, value, action, ord, match_all, match_iq, "
			     "match_message, match_presence_in, "
			     "match_presence_out "
			     ") "
			     "values ('", ID, "', '",
			     join(Items, "', '"), "');"])
		  end, RItems).

del_privacy_lists(LServer, Server, Username) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from privacy_list where username='", Username, "';"]),
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from privacy_list_data where value='", Username++"@"++Server, "';"]),
    ejabberd_odbc:sql_query(
      LServer,
      ["delete from privacy_default_list where username='", Username, "';"]).

add_security_log(LServer, Username, Server, Source, Action, Description, Timestamp) ->
	{{TYear, TMonth, TDay}, {THour, TMin, TSec}} = calendar:now_to_local_time(Timestamp),
	STimestamp = lists:flatten(io_lib:format("~4..0b-~2..0b-~2..0b ~2..0b:~2..0b:~2..0b",
			[TYear, TMonth, TDay, THour, TMin, TSec])),
	ejabberd_odbc:sql_query(LServer,
		["INSERT DELAYED INTO security_logs.ejabberd (username, server, source, action, description, timestamp) "
		"VALUES ('", Username, "', '", Server, "', '", Source, "', '", Action, "', '", Description, "', '", STimestamp, "');"]).

%% Characters to escape
escape($\0) -> "\\0";
escape($\n) -> "\\n";
escape($\t) -> "\\t";
escape($\b) -> "\\b";
escape($\r) -> "\\r";
escape($')  -> "''";
escape($")  -> "\\\"";
escape($\\) -> "\\\\";
escape(C)   -> C.

%% Count number of records in a table given a where clause
count_records_where(LServer, Table, WhereClause) ->
    ejabberd_odbc:sql_query(
      LServer,
      ["select count(*) from ", Table, " ", WhereClause, ";"]).


get_roster_version(LServer, LUser) ->
	ejabberd_odbc:sql_query(LServer,
		["select version from roster_version where username = '", LUser, "'"]).
set_roster_version(LUser, Version) ->
	update_t("roster_version", ["username", "version"], [LUser, Version], ["username = '", LUser, "'"]).
