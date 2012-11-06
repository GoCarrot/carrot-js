# Carrot -- Copyright (C) 2012 Carrot Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Requires from http://code.google.com/p/crypto-js/
# http://crypto-js.googlecode.com/svn/tags/3.0.2/build/components/enc-base64-min.js
# http://crypto-js.googlecode.com/svn/tags/3.0.2/build/rollups/hmac-sha256.js

class Carrot
  @Status =
    NotAuthorized: 'Carrot user has not authorized application.'
    NotCreated: 'Carrot user does not exist.'
    Unknown: 'Carrot user status unknown.'
    ReadOnly: 'Carrot user has not granted \'publish_actions\' permission.'
    Authorized: 'Carrot user authorized.'
    Ok: 'Operation successful.'
    Error: 'Operation unsuccessful.'

  constructor: (appId, udid, appSecret, hostname) ->
    try
      @request = require('request')
    catch err
      @request = null
    @appId = appId
    @udid = udid
    @appSecret = appSecret
    @status = Carrot.Status.Unknown
    @hostname = hostname or "gocarrot.herokuapp.com"

  ajaxGet: (url, callback) ->
    if @request
        @request(url, (error, response, body) =>
          callback(response.statusCode) if callback
          response.end
        )
    else
      $.ajax
        async: true
        url: url
        complete: (jqXHR, textStatus) =>
          callback(jqXHR.status) if callback
    true

  ajaxPost: (url, data, callback) ->
    if @request
        @request.post(url, {'form':data}, (error, response, body) =>
          callback(response.statusCode) if callback
          response.end
        )
    else
      $.ajax
        async: true
        type: 'POST'
        data: data
        url: url
        complete: (jqXHR, textStatus) =>
          callback(jqXHR.status) if callback
    true

  validateUser: (callback) ->
    @ajaxGet("https://#{@hostname}/games/#{@appId}/users/#{@udid}.json",
      (statusCode) =>
        switch statusCode
          when 200
            @status = Carrot.Status.Authorized
          when 401
            @status = Carrot.Status.ReadOnly
          when 403
            @status = Carrot.Status.NotAuthorized
          when 404
            @status = Carrot.Status.NotCreated
          else
            @status = Carrot.Status.Unknown
        callback(@status) if callback
    )

  createUser: (accessToken, callback) ->
    @ajaxPost("https://#{@hostname}/games/#{@appId}/users.json",
      {'access_token': accessToken, 'api_key': @udid},
      (statusCode) =>
        switch statusCode
          when 201
            @status = Carrot.Status.Authorized
          when 401
            @status = Carrot.Status.ReadOnly
          when 404
            @status = Carrot.Status.NotAuthorized
          else
            @status = Carrot.Status.Unknown
        callback(@status)  if callback
    )

  postAchievement: (achievementId, callback) ->
    @postSignedRequest("/me/achievements.json",
      {'achievement_id': achievementId},
      (statusCode) =>
        ret = Carrot.Status.Error
        switch statusCode
          when 200
            ret = Carrot.Status.Ok
          when 201
            ret = Carrot.Status.Ok
          when 401
            @status = Carrot.Status.ReadOnly
          when 404
            @status = Carrot.Status.NotAuthorized
          else
            @status = Carrot.Status.Unknown
        callback(ret) if callback
    )

  postHighScore: (score, leaderboardId, callback) ->
    @postSignedRequest("/me/scores.json",
      {'value': score, 'leaderboard_id': leaderboardId | ""},
      (statusCode) =>
        ret = Carrot.Status.Error
        switch statusCode
          when 200
            ret = Carrot.Status.Ok
          when 201
            ret = Carrot.Status.Ok
          when 401
            @status = Carrot.Status.ReadOnly
          when 404
            @status = Carrot.Status.NotAuthorized
          else
            @status = Carrot.Status.Unknown
        callback(ret) if callback
    )

  postAction: (actionId, objectInstanceId, actionProperties, objectProperties, callback) ->
    actionProperties = if typeof actionProperties is "string" then actionProperties else JSON.stringify(actionProperties || {})
    objectProperties = if typeof objectProperties is "string" then objectProperties else JSON.stringify(objectProperties || {})
    params = {
      'action_id': actionId,
      'action_properties': actionProperties,
      'object_properties': objectProperties
    }
    params['object_instance_id'] = objectInstanceId if objectInstanceId
    @postSignedRequest("/me/actions.json", params,
      (statusCode) =>
        ret = Carrot.Status.Error
        switch statusCode
          when 200
            ret = Carrot.Status.Ok
          when 201
            ret = Carrot.Status.Ok
          when 401
            @status = Carrot.Status.ReadOnly
          when 404
            @status = Carrot.Status.NotAuthorized
          else
            @status = Carrot.Status.Unknown
        callback(ret) if callback
    )

  postSignedRequest: (endpoint, query_params, callback) ->
    url_params = {
      'api_key': @udid,
      'game_id': @appId,
      'request_date': Math.round((new Date()).getTime() / 1000),
      'request_id': @GUID()
    }
    for k, v of query_params
      url_params[k] = v
    keys = (k for k, v of url_params)
    keys.sort()
    url_string = ""
    for k in keys
      url_string = url_string + "#{k}=#{url_params[k]}&"
    url_string = url_string.slice(0, url_string.length - 1);

    sign_string = "POST\n#{@hostname}\n#{endpoint}\n#{url_string}"
    digest = CryptoJS.HmacSHA256(sign_string, @appSecret).toString(CryptoJS.enc.Base64)
    url_params.sig = digest

    @ajaxPost("https://#{@hostname}#{endpoint}", url_params, callback)

  GUID: ->
    S4 = () => return Math.floor(Math.random() * 0x10000).toString(16)

    return (
      S4() + S4() + "-" +
      S4() + "-" +
      S4() + "-" +
      S4() + "-" +
      S4() + S4() + S4()
    );

(exports ? this).Carrot = Carrot
