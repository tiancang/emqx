%%--------------------------------------------------------------------
%% Copyright (c) 2021 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_tls_lib).

-export([ default_versions/0
        , integral_versions/1
        , default_ciphers/0
        , default_ciphers/1
        , integral_ciphers/2
        ]).

-define(IS_STRING_LIST(L), (is_list(L) andalso L =/= [] andalso is_list(hd(L)))).

%% @doc Returns the default supported tls versions.
-spec default_versions() -> [atom()].
default_versions() ->
    OtpRelease = list_to_integer(erlang:system_info(otp_release)),
    integral_versions(default_versions(OtpRelease)).

%% @doc Validate a given list of desired tls versions.
%% raise an error exception if non of them are available.
-spec integral_versions([ssl:tls_version()]) -> [ssl:tls_version()].
integral_versions(Desired) ->
    {_, Available} = lists:keyfind(available, 1, ssl:versions()),
    case lists:filter(fun(V) -> lists:member(V, Available) end, Desired) of
        [] -> erlang:error(#{ reason => no_available_tls_version
                            , desired => Desired
                            , available => Available
                            });
        Filtered ->
            Filtered
    end.

%% @doc Return a list of default (openssl string format) cipher suites.
-spec default_ciphers() -> [string()].
default_ciphers() -> default_ciphers(tls_versions()).

%% @doc Return a list of (openssl string format) cipher suites.
-spec default_ciphers([ssl:tls_version()]) -> [string()].
default_ciphers(['tlsv1.3']) ->
    %% When it's only tlsv1.3 wanted, use 'exclusive' here
    %% because 'all' returns legacy cipher suites too,
    %% which does not make sense since tlsv1.3 can not use
    %% legacy cipher suites.
    ssl:cipher_suites(exclusive, 'tlsv1.3', openssl);
default_ciphers(Versions) ->
    %% assert non-empty
    [_ | _] = dedup(lists:append([ssl:cipher_suites(all, V, openssl) || V <- Versions])).

%% @doc Ensure version & cipher-suites integrity.
-spec integral_ciphers([ssl:tls_version()], binary() | string() | [string()]) -> [string()].
integral_ciphers(Versions, Ciphers) when Ciphers =:= [] orelse Ciphers =:= undefined ->
    %% not configured
    integral_ciphers(Versions, default_ciphers(Versions));
integral_ciphers(Versions, Ciphers) when ?IS_STRING_LIST(Ciphers) ->
    %% ensure tlsv1.3 ciphers if none of them is found in Ciphers
    dedup(ensure_tls1_3_cipher(lists:member('tlsv1.3', Versions), Ciphers));
integral_ciphers(Versions, Ciphers) when is_binary(Ciphers) ->
    %% parse binary
    integral_ciphers(Versions, binary_to_list(Ciphers));
integral_ciphers(Versions, Ciphers) ->
    %% parse comma separated cipher suite names
    integral_ciphers(Versions, string:tokens(Ciphers, ", ")).

%% In case tlsv1.3 is present, ensure tlsv1.3 cipher is added if user
%% did not provide it from config --- which is a common mistake
ensure_tls1_3_cipher(true, Ciphers) ->
    Tls13Ciphers = default_ciphers(['tlsv1.3']),
    case lists:any(fun(C) -> lists:member(C, Tls13Ciphers) end, Ciphers) of
        true  -> Ciphers;
        false -> Tls13Ciphers ++ Ciphers
    end;
ensure_tls1_3_cipher(false, Ciphers) ->
    Ciphers.

%% tlsv1.3 is available from OTP-22 but we do not want to use until 23.
default_versions(OtpRelease) when OtpRelease >= 23 ->
    ['tlsv1.3' | default_tls_versions(22)];
default_versions(_) ->
    ['tlsv1.2','tlsv1.1', tlsv1].

%% Deduplicate a list without re-ordering the elements.
dedup([]) -> [];
dedup([H | T]) -> [H | dedup([I || I <- T, I =/= H])].
