import httpclient, strutils, tables, times, uri, std/[envvars, json]
import awsclient
export awsclient

const
  awsURI = "https://amazonaws.com"

let
  defRegion = getEnv("AWS_DEFAULT_REGION", "us-east-1")

type
  StsClient* = object of AwsClient

proc newStsClient*(creds: AwsCredentials,
                   region: string = defRegion,
                   host: string = awsURI): StsClient =
  let
    # TODO - use some kind of template and compile-time variable to put the correct kernel used to build the sdk in the UA?
    httpclient = newHttpClient("nimaws-sdk/0.3.3; "&defUserAgent.replace(" ", "-").toLower&"; darwin/16.7.0")
    scope = AwsScope(date: getAmzDateString(), region: region, service: "sts")

  var
    endpoint: Uri
    mhost = host

  if mhost.len > 0:
    if mhost.find("http") == -1:
      echo "host should be a valid URI assuming http://"
      mhost = "http://"&host
  else:
    mhost = awsURI
  endpoint = parseUri(mhost)

  return StsClient(httpClient: httpclient, credentials: creds, scope: scope,
                   endpoint: endpoint, isAWS: endpoint.hostname == "amazonaws.com",
                   key: "", key_expires: getTime())

proc getCallerIdentity*(self: var StsClient): StsCallerIdentity =
  let params = {
    "action":  "POST",
    "payload": "Action=GetCallerIdentity&Version=2011-06-15",
  }.toTable
  let res = self.request(params, newHttpHeaders(@[
    ("Content-Type", "application/x-www-form-urlencoded"),
    ("Accept", "application/json"),
  ]))
  if res.code != Http200:
    raise newException(ValueError, res.status)
  let
    jsonResponse = parseJson(res.body())
    identity     = jsonResponse["GetCallerIdentityResponse"]["GetCallerIdentityResult"]
  return StsCallerIdentity(arn:     parseArn(identity["Arn"].getStr()),
                           userId:  identity["UserId"].getStr(),
                           account: identity["Account"].getStr())
