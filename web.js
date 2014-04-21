var express = require('express');
var fs = require('fs');
var exec = require('child_process').exec;

exec('cake build');

var app = express();

app.get('/', function(request, response) {
  response.sendfile("./lib/Carrot.js");
});

app.post('/', function(request, response) {
  response.sendfile("./test.html");
});

var port = process.env.PORT || 5000;
app.listen(port, function() {
  console.log("Listening on " + port);
});
