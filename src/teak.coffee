# Teak -- Copyright (C) 2012 Teak Inc.
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

class Teak
  @Status =
    NotAuthorized: 'Teak user has not authorized application.'
    NotCreated: 'Teak user does not exist.'
    Unknown: 'Teak user status unknown.'
    ReadOnly: 'Teak user has not granted \'publish_actions\' permission.'
    Authorized: 'Teak user authorized.'
    Ok: 'Operation successful.'
    Error: 'Operation unsuccessful.'

  init: (appId, appToken, hostname) ->
    try
      @request = require('request')
    catch err
      @request = null
    @appId = appId
    @appSecret = appToken
    @status = Teak.Status.Unknown
    @hostname = hostname or "gocarrot.com"
    @scheme = ("http" if hostname?.match(/^localhost/)) or "https"

  setUdid: (userId) ->
    @udid = userId

  setSWFObjectID: (objectId) ->
    @swfObjectID = objectId

  getSwf: () ->
    document.getElementById(@swfObjectID)

  swfCallback: (carrotResponse, fbResponse, callbackId) ->
    swf = @getSwf()
    if swf
      swf.teakUiCallback(JSON.stringify({carrotResponse: carrotResponse, fbResponse: fbResponse}), callbackId)

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

  identify: (userId, accessToken, callback) ->
    @udid = userId
    @ajaxPost("#{@scheme}://#{@hostname}/games/#{@appId}/users.json",
      {'access_token': accessToken, 'api_key': @udid},
      (jqXHR) =>
        response = $.parseJSON(jqXHR.responseText);
        switch jqXHR.status
          when 201
            @status = Teak.Status.Authorized
            @userId = response.facebook_id
          when 401
            @status = Teak.Status.ReadOnly
            @userId = response.facebook_id
          when 405
            @status = Teak.Status.NotAuthorized
          else
            @status = Teak.Status.Unknown
        callback(@status)  if callback
    )

  callbackHandler: (callback) ->
    return (jqXHR) =>
      ret = Teak.Status.Error
      switch jqXHR.status
        when 200
          ret = Teak.Status.Ok
        when 201
          ret = Teak.Status.Ok
        when 401
          @status = Teak.Status.ReadOnly
        when 404
          # No change to status, resource not found
          @status = @status
        when 405
          @status = Teak.Status.NotAuthorized
        else
          @status = Teak.Status.Unknown
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

  postAction: (actionId, objectTypeId, objectInstanceId, properties, callback) ->
    actionProperties = if typeof properties is "string" then properties else JSON.stringify(properties || {})
    objectProperties = if typeof properties is "string" then properties else JSON.stringify(properties || {})
    params = {
      'action_id': actionId,
      'object_type_id': objectTypeId,
      'action_properties': actionProperties,
      'object_properties': objectProperties
    }
    params['object_instance_id'] = objectInstanceId if objectInstanceId
    @postSignedRequest("/me/actions.json", params, @callbackHandler(callback))

  uiCallbackHandler: (callback, carrotResponse, fbResponse) ->
    if typeof(callback) == "function"
      callback(carrotResponse, fbResponse)
    else if typeof(callback) == "string" && @getSwf()
      @swfCallback(carrotResponse, fbResponse, callback)

  canMakeFeedPost: (objectInstanceId, callback) ->
    params = {
      'object_instance_id': objectInstanceId
    }
    @postSignedRequest("/me/can_post.json", params, (jqXHR) =>
      carrotResponse = $.parseJSON(jqXHR.responseText)
      @uiCallbackHandler(callback, carrotResponse.code == 200)
    )

  popupFeedPost: (objectInstanceId, objectProperties, callback, postMethod) ->
    if !postMethod? && FB?
      postMethod = FB.ui

    if postMethod?
      actionProperties = if typeof actionProperties is "string" then actionProperties else JSON.stringify(actionProperties || {})
      objectProperties = if typeof objectProperties is "string" then objectProperties else JSON.stringify(objectProperties || {})
      params = {
        'object_properties': objectProperties
      }
      params['object_instance_id'] = objectInstanceId if objectInstanceId
      @postSignedRequest("/me/feed_post.json", params, (jqXHR) =>
        carrotResponse = $.parseJSON(jqXHR.responseText)
        @internal_directFeedPost(carrotResponse, callback, postMethod)
      )

  internal_directFeedPost: (carrotResponse, callback, postMethod) ->
    if !postMethod? && FB?
      postMethod = FB.ui
    if carrotResponse.code == 200
        postMethod(carrotResponse.fb_data,
          (fbResponse) =>
            if fbResponse and fbResponse.post_id
              @ajaxPost("#{@scheme}://parsnip.gocarrot.com/feed_dialog_post", {platform_id: carrotResponse.post_id})

            @uiCallbackHandler(callback, carrotResponse, fbResponse)
        )
      else
        @uiCallbackHandler(callback, carrotResponse)

  reportNotificationClick: (notifId, callback) ->
    @ajaxPost("#{@scheme}://parsnip.gocarrot.com/notification_click", {user_id: @udid, platform_id: notifId})

  reportFeedClick: (postId, callback) ->
    @ajaxPost("#{@scheme}://posts.gocarrot.com/#{postId}/clicks", {clicking_user_id: @udid, sig: "s"},
      (jqXHR) =>
        response = $.parseJSON(jqXHR.responseText).response;
        if response.cascade && response.cascade.method == "sendRequest"
          @sendRequest(response.cascade.arguments.request_id, response.cascade.arguments.opts)
        @uiCallbackHandler(callback, response)
    )

  # Available opts: object_type, object_id, object_properties, filters, suggestions, exclude_ids, max_recipients, data
  sendRequest: (requestId, opts, callback, postMethod) ->
    if !postMethod? && FB?
      postMethod = FB.ui

    if !opts
      opts = {}

    if postMethod?
      params = {
        'request_id' : requestId
        'object_properties' : JSON.stringify(opts['object_properties'] || {})
      }
      if opts['object_type'] && opts['object_id']
        params['object_type'] = opts['object_type']
        params['object_instance_id'] = opts['object_id']

      @postSignedRequest("/me/request.json", params, (jqXHR) =>
        carrotResponse = $.parseJSON(jqXHR.responseText)
        fb_data = $.extend({}, opts, carrotResponse.fb_data)
        @internal_directRequest(carrotResponse, callback, postMethod);
      )

  hasRequestOfOpportunity: (opts, callback) ->
    if !opts
      opts = {}

    params = {
      'object_properties' : JSON.stringify(opts['object_properties'] || {})
    }

    @postSignedRequest("/me/request_of_opportunity.json", params, (jqXHR) =>
      carrotResponse = $.parseJSON(jqXHR.responseText)
      if(carrotResponse.code == 200) {
        @requestOfOpportunity = carrotResponse
        callback(true) if callback
      } else {
        callback(false) if callback
      }
    )

  sendRequestOfOpporunity: (callback) ->
    if @requestOfOpportunity
      internal_directRequest(@requestOfOpportunity, callback)
    @requestOfOpportunity = undefined

  internal_directRequest: (carrotResponse, callback, postMethod) ->
    if !postMethod? && FB?
      postMethod = FB.ui
    if carrotResponse.code == 200
        postMethod(carrotResponse.fb_data,
          (fbResponse) =>
            if(fbResponse && fbResponse.request)
              @ajaxPost("#{@scheme}://posts.gocarrot.com/requests/#{carrotResponse.request_id}/ids", {platform_id: fbResponse.request})
              if fbResponse && fbResponse.to
                for receivingUser in fbResponse.to
                  @ajaxPost("#{@scheme}://parsnip.gocarrot.com/request_send", {platform_id: carrotResponse.request_id, posting_user_id: @udid, user_id: receivingUser})

            @uiCallbackHandler(callback, carrotResponse, fbResponse)
        )
      else
        @uiCallbackHandler(callback, carrotResponse)


  acceptRequest: (requestId, callback) ->
    @ajaxPost("#{@scheme}://posts.gocarrot.com/requests/#{requestId}/clicks", {clicking_user_id: @udid, sig: "s"},
      (jqXHR) =>
        response = $.parseJSON(jqXHR.responseText).response;
        if response.cascade && response.cascade.method == "sendRequest"
          @sendRequest(response.cascade.arguments.request_id, response.cascade.arguments.opts)
        @uiCallbackHandler(callback, response)
    )

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

realTeak = new Teak()
snippetTeak = (exports ? this).teak
if snippetTeak
  for queuedCall in snippetTeak
    methodName = queuedCall.splice(0, 1)[0];
    realTeak[methodName].apply(realTeak, queuedCall)

(exports ? this).teak = realTeak
