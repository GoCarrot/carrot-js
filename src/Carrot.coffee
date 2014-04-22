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

  @trackLoad: (appId, signedRequest) ->
    img = new Image()
    img.src = 'https://gocarrot.com/tracking?app_id=' + appId + '&signed_request=' + signedRequest

  constructor: (appId, udid, appSecret, hostname) ->
    try
      @request = require('request')
    catch err
      @request = null
    @appId = appId
    @udid = udid
    @appSecret = appSecret
    @status = Carrot.Status.Unknown
    @hostname = hostname or "gocarrot.com"
    @scheme = ("http" if hostname?.match(/^localhost/)) or "https"

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
          callback(jqXHR) if callback
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
          callback(jqXHR) if callback
    true

  validateUser: (accessToken, callback) ->
    @ajaxPost("#{@scheme}://#{@hostname}/games/#{@appId}/users.json",
      {'access_token': accessToken, 'api_key': @udid},
      (jqXHR) =>
        response = $.parseJSON(jqXHR.responseText);
        switch jqXHR.status
          when 201
            @status = Carrot.Status.Authorized
            @userId = response.facebook_id
          when 401
            @status = Carrot.Status.ReadOnly
            @userId = response.facebook_id
          when 405
            @status = Carrot.Status.NotAuthorized
          else
            @status = Carrot.Status.Unknown
        callback(@status)  if callback
    )

  callbackHandler: (callback) ->
    return (jqXHR) =>
      ret = Carrot.Status.Error
      switch jqXHR.status
        when 200
          ret = Carrot.Status.Ok
        when 201
          ret = Carrot.Status.Ok
        when 401
          @status = Carrot.Status.ReadOnly
        when 404
          # No change to status, resource not found
          @status = @status
        when 405
          @status = Carrot.Status.NotAuthorized
        else
          @status = Carrot.Status.Unknown
      if callback
        return callback(ret)
      else
        return ret

  postAchievement: (achievementId, callback) ->
    @postSignedRequest("/me/achievements.json",
      {'achievement_id': achievementId}, @callbackHandler(callback))

  postHighScore: (score, callback) ->
    @postSignedRequest("/me/scores.json",
      {'value': score}, @callbackHandler(callback))

  postAction: (actionId, objectInstanceId, actionProperties, objectProperties, callback) ->
    actionProperties = if typeof actionProperties is "string" then actionProperties else JSON.stringify(actionProperties || {})
    objectProperties = if typeof objectProperties is "string" then objectProperties else JSON.stringify(objectProperties || {})
    params = {
      'action_id': actionId,
      'action_properties': actionProperties,
      'object_properties': objectProperties
    }
    params['object_instance_id'] = objectInstanceId if objectInstanceId
    @postSignedRequest("/me/actions.json", params, @callbackHandler(callback))

  popupFeedPost: (actionId, objectInstanceId, actionProperties, objectProperties, callback) ->
    if FB?
      actionProperties = if typeof actionProperties is "string" then actionProperties else JSON.stringify(actionProperties || {})
      objectProperties = if typeof objectProperties is "string" then objectProperties else JSON.stringify(objectProperties || {})
      params = {
        'action_id': actionId,
        'action_properties': actionProperties,
        'object_properties': objectProperties
      }
      params['object_instance_id'] = objectInstanceId if objectInstanceId
      @postSignedRequest("/me/feed_post.json", params, (jqXHR) =>
        FB.ui(jqXHR.responseJSON.fb_data,
          (response) ->
            if response and response.post_id
              @ajaxPost("#{@scheme}://parsnip.gocarrot.com/feed_dialog_post", {platform_id: jqXHR.responseJSON.post_id})

            callback(jqXHR.responseJSON) if callback
        )
      )


  getTweet: (actionId, objectInstanceId, actionProperties, objectProperties, callback) ->
    actionProperties = if typeof actionProperties is "string" then actionProperties else JSON.stringify(actionProperties || {})
    objectProperties = if typeof objectProperties is "string" then objectProperties else JSON.stringify(objectProperties || {})
    params = {
      'action_id': actionId,
      'action_properties': actionProperties,
      'object_properties': objectProperties
    }
    params['object_instance_id'] = objectInstanceId if objectInstanceId
    @getSignedRequest("/me/template_post.json", params, (jqXHR) -> callback(jqXHR.responseJSON) if callback)

  showTweet: (actionId, objectInstanceId, actionProperties, objectProperties, callback) ->
    @getTweet actionId, objectInstanceId, actionProperties, objectProperties, (reply) ->
      callback(reply) if callback
      if reply
        width = 512
        height = 258
        leftPosition = (window.screen.width / 2) - ((width / 2))
        topPosition = (window.screen.height / 2) - ((height / 2))
        url = "https://twitter.com/intent/tweet?text=" + encodeURIComponent(reply.tweet.contents) + "&url=" + encodeURIComponent(reply.tweet.short_url)
        window.open(url, "Twitter", "status=no,height=" + height + ",width=" + width + ",resizable=no,left=" + leftPosition + ",top=" + topPosition + ",screenX=" + leftPosition + ",screenY=" + topPosition + ",toolbar=no,menubar=no,scrollbars=no,location=yes,directories=no,dialog=yes")

  getSignedRequest: (endpoint, query_params, callback) ->
    query_params['_method'] = "GET"
    @doSignedRequest(endpoint, query_params, callback)

  postSignedRequest: (endpoint, query_params, callback) ->
    @doSignedRequest(endpoint, query_params, callback)

  doSignedRequest: (endpoint, query_params, callback) ->
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

    sign_string = "POST\n#{@hostname.split(':')[0]}\n#{endpoint}\n#{url_string}"
    digest = CryptoJS.HmacSHA256(sign_string, @appSecret).toString(CryptoJS.enc.Base64)
    url_params.sig = digest

    @ajaxPost("#{@scheme}://#{@hostname}#{endpoint}", url_params, callback)

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
