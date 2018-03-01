xquery version "1.0-ml";

import module namespace json = "http://marklogic.com/xdmp/json" at "/MarkLogic/json/json.xqy";
import module namespace cfg = "http://www.marklogic.com/data-explore/lib/config" at "/server/lib/config.xqy";
import module namespace check-user-lib = "http://www.marklogic.com/data-explore/lib/check-user-lib" at "/server/lib/check-user-lib.xqy" ;
import module namespace wl = "http://marklogic.com/data-explore/lib/wizard-lib" at "/server/lib/wizard-lib.xqy";
import module namespace xu = "http://marklogic.com/data-explore/lib/xdmp-utils" at "/server/lib/xdmp-utils.xqy"; 
import module namespace lib-adhoc = "http://marklogic.com/data-explore/lib/adhoc-lib" at "/server/lib/adhoc-lib.xqy";
import module namespace nl = "http://marklogic.com/data-explore/lib/namespace-lib"  at "/server/lib/namespace-lib.xqy";
import module namespace ll = "http://marklogic.com/data-explore/lib/logging-lib"  at "/server/lib/logging-lib.xqy";

declare private function local:response($profile as node(), $root-element as xs:string, $type as xs:string) as node()* {
  let $response := json:object()
  let $type-label := if ($type eq "query") then "Query" else "View"
  let $field-label := if ($type eq "query") then "Form Field:" else "Column Name:"
  let $has-json-nodes := $profile/paths/path/@type = "object"
  let $possible-roots := (if ($has-json-nodes) then "/" else (), $profile/paths/path/@path-ns ! fn:concat("/", .))
  let $mapped-ns := $profile/namespaces/ns ! object-node { 
    "abbrv": fn:string(./@prefix),
    "uri": fn:string(.)
  }
  let $fields := for $path in $profile/paths/path[@type = ("text", "boolean", "number", "null", "element")]
    let $mapped-tokens := $path/token ! fn:string-join((./@prefix,fn:string(.)),":")
    let $xpath := fn:concat( "/" , fn:string-join($mapped-tokens, "/"))
    return object-node {
      "label": $field-label,
      "dataType": fn:string(if ($path/@type eq "element") then "text" else $path/@type),
      "xpath": fn:string(wl:collapse-xpath($has-json-nodes, $xpath)),
      "xpathNormal": $xpath,
      "elementName": fn:string-join(($path/@prefix, $path/@name), ":")
    }
  
  return (
    map:put($response, "type", $type-label),
    map:put($response, "possibleRoots", json:to-array($possible-roots)),
    map:put($response, "rootElement", $root-element),
    map:put($response, "databases", json:to-array(lib-adhoc:get-databases())),
    map:put($response, "namespaces", json:to-array($mapped-ns)),
    map:put($response, "fields", json:to-array($fields)),
    xdmp:to-json($response)
  )
};

(: returns a summary of namespaces and paths given a sequence of nodes :)
declare function local:profile-nodes($roots as node()*) as node()
{
  let $namespaces := json:object(), $paths := json:object() (: json:object retains insert sequence :)
  let $_ := for $root in $roots
                for $node in $root/descendant-or-self::*
                    let $root-to-node := $node/ancestor-or-self::*
                    let $path-tokens := for $n in $root-to-node
                    let $qname := fn:node-name($n)
                    let $prefix := nl:resolve-namespace-prefix($qname, $namespaces)
                return element token {
                  if ($prefix) then attribute prefix { $prefix } else (),
                  fn:local-name-from-QName($qname)
                }
            let $path-ns := fn:string-join($path-tokens ! fn:string-join((./@prefix, .), ":") , "/")
            let $last-token := $path-tokens[fn:last()]
            let $node-path := element path {
              attribute name { $last-token },
              $last-token/@prefix,
              attribute path-ns { $path-ns },
              attribute type { xdmp:node-kind($node) },
              $path-tokens
            }
            return if (map:contains($paths, $path-ns))
               then ()
            else
              map:put($paths, $path-ns, $node-path)

  return element profile {
    element namespaces {
      attribute count { map:count($namespaces) },
      map:keys($namespaces) ! element ns {
        attribute prefix { map:get($namespaces, .) },
        .
      }
    },
    element paths {
      map:keys($paths) ! map:get($paths, .)
    },
    element metrics {
      element elapsed-time { xdmp:elapsed-time() }
    }
  }
};

declare function local:process() {
  let $payload := xdmp:get-request-body()
  let $database := $payload/database
  let $ns := $payload/ns
  let $root-name := $payload/name
  let $type := $payload/type

  let $eval-expr := if ($root-name eq "/") then "/" else fn:concat(if (fn:string-length($ns) le 0) then '' else 'qn:', $root-name)
  let $max-samples := 100
  let $eval := fn:concat(
    if (fn:string-length($ns) le 0) then '' else 'declare namespace qn ="' || $ns || '"; ',
    'cts:search(/' || $eval-expr || ', (), ("unfiltered", "score-random"))[1 to ' || $max-samples || ']'
  )
  let $nodes-to-sample := xu:eval(
    $eval, 
    (), 
    <options xmlns="xdmp:eval">
      <database>{ xdmp:database($database) }</database>
    </options>)

  let $profile := local:profile-nodes($nodes-to-sample)
  let $_ := ll:trace($profile)
  let $root-element := fn:concat("/", if (fn:string-length($ns) le 0) then () else $ns||":", $root-name)
  
  return local:response($profile, $root-element, $type)
};


if (check-user-lib:is-logged-in() and check-user-lib:is-wizard-user()) 
then local:process()
else xdmp:set-response-code(401, "User is not authorized.")
