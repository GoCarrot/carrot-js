var express = require('express');
var fs = require('fs');
var exec = require('child_process').exec;

exec('cake build');

var app = express();

app.get('/', function(request, response) {
  response.sendfile("./lib/Carrot.js");
  // response.set('Content-Type', 'application/javascript');
  // fs.readFile('./lib/Carrot.js', function(err, data) {
  //   response.send(data);
  // });
});

var port = process.env.PORT || 5000;
app.listen(port, function() {
  console.log("Listening on " + port);
});
