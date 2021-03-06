xquery version "1.0-ml";

import module namespace cd = "http://marklogic.com/data-explore/lib/check-database-lib" at "/server/lib/check-database-lib.xqy" ;
import module namespace check-user-lib = "http://www.marklogic.com/data-explore/lib/check-user-lib" at "/server/lib/check-user-lib.xqy" ;
import module namespace to-json = "http://marklogic.com/data-explore/lib/to-json" at "/server/lib/to-json-lib.xqy";
import module namespace admin = "http://marklogic.com/xdmp/admin"  at "/MarkLogic/admin.xqy";
import module namespace ll = "http://marklogic.com/data-explore/lib/logging-lib"  at "/server/lib/logging-lib.xqy";
declare option xdmp:mapping "false";
(: /api/users/me/ :)
declare function local:get-user(){
    cd:check-database(),
    let $_ := ll:trace("api-users:get-user ")

    let $user-id := xdmp:get-request-field("id")
    let $_ := ll:trace("api-users:get-user " || $user-id)

    return 
        if (fn:not(check-user-lib:is-logged-in())) then
            fn:false()
        else
            let $role := 
                if (check-user-lib:is-admin() or check-user-lib:is-wizard-user()) then
                    "wizard-user"
                else if (check-user-lib:is-search-user()) then
                    "search-user"
                else
                    "guest"       
            return 
               to-json:to-json(
                    <user>
                        <name>{xdmp:get-current-user()}</name>
                        <role>{$role}</role>
                    </user>
                )
};
let $_ := ll:trace("FROM: /server/endpoints/api-users.xqy")
let $response :=
       if (check-user-lib:is-logged-in()) then
          (local:get-user())
        else (xdmp:set-response-code(401,"User is not authorized."))
return $response