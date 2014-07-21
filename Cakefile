# Mathtastic Cakefile automatically builds output files when files change.
# It generates output test files, and generates docco pages for annotated
# source code.
#

fs               = require 'fs'
path             = require 'path'
{spawn, exec}    = require 'child_process'
CoffeeScript     = require 'coffee-script'
{parser, uglify} = require 'uglify-js'


Array::unique = ->
  output = {}
  output[@[key]] = @[key] for key in [0...@length]
  value for key, value of output

resolveSource = (source) ->
  return source if not source.match(/([\*\?])/)
  regex_str = path.basename(source)
    .replace(/\./g, "\\$&")
    .replace(/\*/,".*")
    .replace(/\?/,".")
  regex = new RegExp('^(' + regex_str + ')$')
  file_path = path.dirname(source)
  files = fs.readdirSync file_path
  return (path.join(file_path,file) for file in files when file.match regex)  

class EzCakeOven
  constructor: (config_file) ->
    @options = {
      # Default options
    }
    return this.load_options(config_file)

  load_options: (file, success_callback) ->
    try
      @options = JSON.parse "#{fs.readFileSync file}"
      if @options == undefined
        return console.log "Error parsing input file #{file}"

      this._generate_test_filenames() if @options.config.tests
      success_callback(this) if typeof success_callback is 'function'
    catch e
      console.log "Error loading configuration file #{file} - #{e}"

  watch: (change_tasks, notify_callback) ->
    for file in this.all_files()
      # Coffeescript wasn't scoping file correctly-
      # without this closure the file name displayed
      # is incorrect.
      ((file) ->
        fs.watchFile file, (curr, prev) ->
          if +curr.mtime isnt +prev.mtime
            console.log "Saw change in #{file}"
            invoke change for change in change_tasks
          return
      )(file)
    this

  build: (notify_callback) ->
    file_name = null; file_contents = null
    try
      for javascript, sources of @options.files
        continue if sources.length == 0

        resolved = []
        resolved = resolved.concat(resolveSource(src)) for src in sources
        resolved.unique()

        code = ''
        js_code = ''
        all_files = []
        # Compile all source files twice.  The first time is a convenience for developing so that syntax
        # errors show up in the proper file
        for source in resolved
          file_name = source
          file_contents = "#{fs.readFileSync source}"

          js_suffix = ".js"
          if(file_name.indexOf(js_suffix, file_name.length - js_suffix.length) != -1)
            js_code += file_contents
          else
            code += CoffeeScript.compile file_contents
            all_files.push file_contents

        # Build the final master coffee file (so all source files automatically share scope with each other)
        code = CoffeeScript.compile all_files.join "\n\n"
        code += js_code
        # Write the javascript version
        this._write_javascript javascript, code
        # If minify then run uglify on the output javascript and produce a .min.js version of the file
        unless process.env.MINIFY is 'false'
          this._write_javascript javascript.replace(/\.js$/,'.min.js'), (
            uglify.gen_code uglify.ast_squeeze uglify.ast_mangle parser.parse code
          )
      # If a callback has been specified, invoke it to signal the completion of a build
      notify_callback() if typeof notify_callback is 'function'
    catch e
      # Catch any compile errors and report them
      this._compile_error e, file_name, file_contents

  # Gather a list of unique source files.
  #
  all_files: () ->
    all_sources = []
    for javascript, sources of @options.files
      resolved = []
      resolved = resolved.concat(resolveSource(src)) for src in sources
      for source in resolved
        all_sources.push source
    all_sources.unique()

  build_docco_pages: () ->
    files = @options.files["lib/Carrot.js"].slice()
    resolved = []
    resolved = resolved.concat(resolveSource(src)) for src in files
    resolved.unique()
    files_string = resolved.join(" ")
    console.log "Generating docco pages for files: #{files_string}"

    # Run docco over all the files
    exec "docco #{files_string}"

  run_tests: () ->
    child = exec 'phantomjs ./src/run-qunit.js ./tests.html', (error, stdout, stderr) ->
      console.log('stdout: ' + stdout)
      if (error != null)
        console.log('stderr: ' + stderr)
        console.log('exec error: ' + error)

  #
  # Write files with a header
  #
  _write_javascript: (filename, body) ->
    fs.writeFileSync filename, """
  // Carrot -- Copyright (C) 2012-2014 GoCarrot, Inc.
  //
  // Licensed under the Apache License, Version 2.0 (the "License");
  // you may not use this file except in compliance with the License.
  // You may obtain a copy of the License at
  //
  //     http://www.apache.org/licenses/LICENSE-2.0
  //
  // Unless required by applicable law or agreed to in writing, software
  // distributed under the License is distributed on an "AS IS" BASIS,
  // WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  // See the License for the specific language governing permissions and
  // limitations under the License.
  #{body}
  """
    console.log "Wrote #{filename}"

  _compile_error: (error, file_name, file_contents) ->
    line = error.message.match /line ([0-9]+):/
    if line && line[1]
      line = parseInt(line[1])
      contents_lines = file_contents.split "\n"
      first = if line-4 < 0 then 0 else line-4
      last  = if line+3 > contents_lines.size then contents_lines.size else line+3
      console.log "Error compiling #{file_name}. \"#{error.message}\"\n"
      index = 0
      for line in contents_lines[first...last]
        index++
        line_number = first + 1 + index
        console.log "#{(' ' for [0..(3-(line_number.toString().length))]).join('')} #{line}"
    else
      console.log """
  Error compiling #{file_name}:

    #{error.message}

  """

#---

builder = null
get_builder = () ->
  builder ?= new EzCakeOven('Cakefile.json')

task 'build', 'build from source', build = (cb) ->
  get_builder().build cb
task 'watch', 'watch src/ for changes and build project', ->
  get_builder().watch ['docs','build','test']
task 'docs', 'Generate annotated source code documentation pages', ->
  get_builder().build_docco_pages()
task 'test', 'Run q-unit tests', ->
  get_builder().run_tests()

