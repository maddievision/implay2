/***************************************************************************
 * IMPLAY
 * Andrew Lim & Bunnie Curtis
 * 2013-12-07 v1
 * 2014-05-28 v2
 *
 * Agent Code
 *
 ***************************************************************************/

//Firebase Auth
const FIREBASE_URL = "https://<your-firebase-subdomain>.firebaseio.com/"
const FIREBASE_AUTH = "<your-firebase-auth-key>"
const DEFAULT_SONG = "l16efg/c/>c"
const SONG_ROOT = "/songs"
/***************************************************************************
 * INCLUDES
 ***************************************************************************/

function StringReplace(string, original, replacement)
{
  // make a regexp that will match the substring to be replaced
  //
  local expression = regexp(original);

  local result = "";
  local position = 0;

  // find the first match
  //
  local captures = expression.capture(string);

  while (captures != null)
  {
    foreach (i, capture in captures)
    {
      // copy from the current position to the start of the match
      //
      result += string.slice(position, capture.begin);

      // add the replacement substring instead of the original
      //
      result += replacement;

      position = capture.end;
    }

    // find the next match
    //
    captures = expression.capture(string, position);
  }

  // add any remaining part of the string after the last match
  //
  result += string.slice(position);

  return result;
}

    /***************************************************************************
     * Firebase Class
     * https://github.com/beardedinventor/ElectricImp-FirebaseIO/blob/master/firebase.agent.nut
     ***************************************************************************/

        const NEWLINE = "\n";

        class Firebase {
            // General
            baseUrl = null;             // base url of your Firebase
            auth = null;                // Auth key (if auth is enabled)
            
            // For REST calls:
            defaultHeaders = { "Content-Type": "application/json" };
            
            // For Streaming:
            streamingHeaders = { "accept": "text/event-stream" };
            streamingRequest = null;    // The request object of the streaming request
            data = null;                // Current snapshot of what we're streaming
            callbacks = null;           // List of callbacks for streaming request
            
            /***************************************************************************
             * Constructor
             * Returns: FirebaseStream object
             * Parameters:
             *      baseURL - the base URL to your Firebase (https://username.firebaseio.com)
             *      auth - the auth token for your Firebase
             **************************************************************************/
            constructor(_baseUrl, _auth) {
                this.baseUrl = _baseUrl;
                this.auth = _auth;
                this.data = {}; 
                this.callbacks = {};
            }
            
            /***************************************************************************
             * Attempts to open a stream
             * Returns: 
             *      false - if a stream is already open
             *      true -  otherwise
             * Parameters:
             *      path - the path of the node we're listending to (without .json)
             *      autoReconnect - set to false to close stream after first timeout
             *      onError - custom error handler for streaming API 
             **************************************************************************/
            function stream(path = "", autoReconnect = true, onError = null) {
                // if we already have a stream open, don't open a new one
                if (streamingRequest) return false;
                 
                if (onError == null) onError = _defaultErrorHandler.bindenv(this);
                local request = http.get(_buildUrl(path), streamingHeaders);
                this.streamingRequest = request.sendasync(

                    function(resp) {
                        server.log("Stream Closed (" + resp.statuscode + ": " + resp.body +")");
                        // if we timed out and have autoreconnect set
                        if (resp.statuscode == 28 && autoReconnect) {
                            stream(path, autoReconnect, onError);
                            return;
                        }
                        if (resp.statuscode == 307) {
                            if("location" in resp.headers) {
                                // set new location
                                local location = resp.headers["location"];
                                local p = location.find(path);
                                this.baseUrl = location.slice(0, p);

                                stream(path, autoReconnect, onError);
                                return;
                            }
                        }
                    }.bindenv(this),
                    
                    function(messageString) {
                        //try {
                            server.log("MessageString: " + messageString);
                            local message = _parseEventMessage(messageString);
                            local changedRoot = _setData(message);
                            _findAndExecuteCallback(message.path, changedRoot);
                        //} catch(ex) {
                            // if an error occured, invoke error handler
                            //onError([{ message = "Squirrel Error - " + ex, code = -1 }]);
                        //}

                    }.bindenv(this)
                    
                );
                
                // Return true if we opened the stream
                return true;
            }

            /***************************************************************************
             * Returns whether or not there is currently a stream open
             * Returns: 
             *      true - streaming request is currently open
             *      false - otherwise
             **************************************************************************/
            function isStreaming() {
                return (streamingRequest != null);
            }
            
            /***************************************************************************
             * Closes the stream (if there is one open)
             **************************************************************************/
            function closeStream() {
                if (streamingRequest) { 
                    streamingRequest.cancel();
                    streamingRequest = null;
                }
            }
            
            /***************************************************************************
             * Registers a callback for when data in a particular path is changed.
             * If a handler for a particular path is not defined, data will change,
             * but no handler will be called
             * 
             * Returns: 
             *      nothing
             * Parameters:
             *      path     - the path of the node we're listending to (without .json)
             *      callback - a callback function with one parameter (data) to be 
             *                 executed when the data at path changes
             **************************************************************************/
            function on(path, callback) {
                callbacks[path] <- callback;
            }
            
            /***************************************************************************
             * Reads data from the specified path, and executes the callback handler
             * once complete.
             *
             * NOTE: This function does NOT update firebase.data
             * 
             * Returns: 
             *      nothing
             * Parameters:
             *      path     - the path of the node we're reading
             *      callback - a callback function with one parameter (data) to be 
             *                 executed once the data is read
             **************************************************************************/    
             function read(path, callback = null, errcb = null) {
                http.get(_buildUrl(path), defaultHeaders).sendasync(function(res) {
                    if (res.statuscode != 200) {
                        server.log("Read: Firebase response: " + res.statuscode + " => " + res.body)
                        if (errcb) errcb();
                    } else {
                        local data = null;
                        try {
                            data = http.jsondecode(res.body);
                        } catch (err) {
                            server.log("Read: JSON Error: " + res.body);
                            return;
                        }
                        if (callback) callback(data);
                    }
                }.bindenv(this));
            }
            
            /***************************************************************************
             * Pushes data to a path (performs a POST)
             * This method should be used when you're adding an item to a list.
             * 
             * NOTE: This function does NOT update firebase.data
             * Returns: 
             *      nothing
             * Parameters:
             *      path     - the path of the node we're pushing to
             *      data     - the data we're pushing
             **************************************************************************/    
            function push(path, data) {
                http.post(_buildUrl(path), defaultHeaders, http.jsonencode(data)).sendasync(function(res) {
                    if (res.statuscode != 200) {
                        server.log("Push: Firebase response: " + res.statuscode + " => " + res.body)
                    }
                }.bindenv(this));
            }
            
            /***************************************************************************
             * Writes data to a path (performs a PUT)
             * This is generally the function you want to use
             * 
             * NOTE: This function does NOT update firebase.data
             * 
             * Returns: 
             *      nothing
             * Parameters:
             *      path     - the path of the node we're writing to
             *      data     - the data we're writing
             **************************************************************************/    
            function write(path, data) {
                http.put(_buildUrl(path), defaultHeaders, http.jsonencode(data)).sendasync(function(res) {
                    if (res.statuscode != 200) {
                        server.log("Write: Firebase response: " + res.statuscode + " => " + res.body)
                    }
                }.bindenv(this));
            }
            
            /***************************************************************************
             * Updates a particular path (performs a PATCH)
             * This method should be used when you want to do a non-destructive write
             * 
             * NOTE: This function does NOT update firebase.data
             * 
             * Returns: 
             *      nothing
             * Parameters:
             *      path     - the path of the node we're patching
             *      data     - the data we're patching
             **************************************************************************/    
            function update(path, data) {
                http.request("PATCH", _buildUrl(path), defaultHeaders, http.jsonencode(data)).sendasync(function(res) {
                    if (res.statuscode != 200) {
                        server.log("Update: Firebase response: " + res.statuscode + " => " + res.body)
                    } 
                }.bindenv(this));
            }
            
            /***************************************************************************
             * Deletes the data at the specific node (performs a DELETE)
             * 
             * NOTE: This function does NOT update firebase.data
             * 
             * Returns: 
             *      nothing
             * Parameters:
             *      path     - the path of the node we're deleting
             **************************************************************************/        
            function remove(path) {
                http.httpdelete(_buildUrl(path), defaultHeaders).sendasync(function(res) {
                    if (res.statuscode != 200) {
                        server.log("Delete: Firebase response: " + res.statuscode + " => " + res.body)
                    }
                });
            }
            
            /************ Private Functions (DO NOT CALL FUNCTIONS BELOW) ************/
            // Builds a url to send a request to
            function _buildUrl(path) {
                local url = FIREBASE_URL + path + ".json";
                if (auth != null) url = url + "?auth=" + auth;
                return url;
            }

            // Default error handler
            function _defaultErrorHandler(errors) {
                foreach(error in errors) {
                    server.log("ERROR " + error.code + ": " + error.message);
                }
            }

            // parses event messages
            function _parseEventMessage(text) {
                // split message into parts
                local lines = split(text, NEWLINE);
                
                // get the event
                local eventLine = lines[0];
                local event = eventLine.slice(7);
                
                // get the data
                local dataLine = lines[1];
                local dataString = dataLine.slice(6);
            
                // pull interesting bits out of the data
                local d = http.jsondecode(dataString);
                local path = d.path;
                local messageData = d.data;
                
                // return a useful object
                return { "event": event, "path": path, "data": messageData };
            }

            // Sets data and returns root of changed data
            function _setData(message) {
                // base case - refresh everything
                if (message.event == "put" && message.path =="/") {
                    data = (message.data != null) ? message.data : {};
                    return data
                }
                
                local pathParts = split(message.path, "/");
                
                local currentData = data;
                local parent = data;
                
                foreach(part in pathParts) {
                    parent=currentData;
                    
                    if (part in currentData) currentData = currentData[part];
                    else {
                        currentData[part] <- {};
                        currentData = currentData[part];
                    }
                }
                
                local key = pathParts.len() > 0 ? pathParts[pathParts.len()-1] : null;
                
                if (message.event == "put") {
                    if (message.data == null) {
                        if (key != null) delete parent[key];
                        else data = {};
                        return null;
                    }
                    else {
                        if (key != null) parent[key] <- message.data;
                        else data[key] <- message.data;
                    }
                }
                
                if (message.event == "patch") {
                    foreach(k,v in message.data) {
                        if (key != null) parent[key][k] <- v
                        else data[k] <- v;
                    }
                }
                
                return (key != null) ? parent[key] : data;
            }

            // finds and executes a callback after data changes
            function _findAndExecuteCallback(path, callbackData) {
                local pathParts = split(path, "/");
                local key = "";
                for(local i = pathParts.len() - 1; i >= 0; i--) {
                    key = "";
                    for (local j = 0; j <= i; j++) key = key + "/" + pathParts[j];
                    if (key in callbacks || key + "/" in callbacks) break;
                }
                if (key + "/" in callbacks) key = key + "/";
                if (key in callbacks) callbacks[key](callbackData);
            }
        }

//access through agent URL

rxNote <- regexp(@"^([a-g])([+s])?");
rxRepeat <- regexp(@"^\\");
rxExtend <- regexp(@"^\.");
rxRest <- regexp(@"^/");
rxLength <- regexp(@"^l([0-9]{1,3})");
rxOctave <- regexp(@"^o([0-9]{1,2})");
rxDuty <- regexp(@"^p([0-9])");
rxGate <- regexp(@"^m([0-9]{1,2})");
rxTempo <- regexp(@"^t([0-9]{1,3})");
rxDownOctave <- regexp(@"^<([0-9]{0,1})");
rxUpOctave <- regexp(@"^>([0-9]{0,1})");
rxDownDetune <- regexp(@"^x-([0-9]{1,2})");
rxUpDetune <- regexp(@"^x([0-9]{1,2})");
rxInclude <- regexp(@"^\$([A-Za-z0-9_/]+)");
rxComment <- regexp(@"^#([^\s]*)");
rxLoopStart <- regexp(@"^\[");
rxLoopCoda <- regexp(@"^:");
rxLoopEnd <- regexp(@"^\]([0-9]{1,2})");
rxMacroDef <- regexp(@"^@(\w+)\{([^\}]*)\}");
rxMacroCall <- regexp(@"^@(\w+)");
rxWhite <- regexp(@"^(\s+)");

partials <- {}

NOTE_MAP <- {
  c=0,d=2,e=4,f=5,g=7,a=9,b=11  
};

function tryPattern(rx, s, i) {
  local res = rx.capture(s, i);
  if (res == null) return null;
  local tok = res.map(function (r) { return s.slice(r.begin, r.end); });
  return [tok, res[0].end];
}

MACROS <- {}

function parseMML(s, cb, i=0, cmds=[]) {
  local tok = null
  
  while (i < s.len()) {
      if (tok = tryPattern(rxNote, s, i)) {
          local mod = 0;
          if (tok[0][2] == "+" || tok[0][2] == "s") {
              mod = 1;
          }
          local nn = NOTE_MAP[tok[0][1]] + mod;
          cmds.push(["note", nn]);
      }
      else if (tok = tryPattern(rxRepeat, s, i)) {
          cmds.push(["repeat"]);
      }
      else if (tok = tryPattern(rxExtend, s, i)) {
          cmds.push(["extend"]);
      }
      else if (tok = tryPattern(rxRest, s, i)) {
          cmds.push(["rest"]);
      }
      else if (tok = tryPattern(rxLength, s, i)) {
          cmds.push(["len", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxOctave, s, i)) {
          cmds.push(["oct", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxDownOctave, s, i)) {
          local n = 1;
          if (tok[0][1].len() > 0) {
              n = tok[0][1].tointeger()
          }
          cmds.push(["octdn", n]);
      }
      else if (tok = tryPattern(rxUpOctave, s, i)) {
          local n = 1;
          if (tok[0][1].len() > 0) {
              n = tok[0][1].tointeger()
          }
          cmds.push(["octup", n]);
      }
      else if (tok = tryPattern(rxDuty, s, i)) {
          cmds.push(["duty", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxDownDetune, s, i)) {
          cmds.push(["tunedn", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxUpDetune, s, i)) {
          cmds.push(["tuneup", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxGate, s, i)) {
          cmds.push(["gate", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxTempo, s, i)) {
          cmds.push(["tempo", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxLoopStart, s, i)) {
          cmds.push(["lpstart"]);
      }
      else if (tok = tryPattern(rxLoopCoda, s, i)) {
          cmds.push(["lpcoda"]);
      }
      else if (tok = tryPattern(rxLoopEnd, s, i)) {
          cmds.push(["lpend", tok[0][1].tointeger()]);
      }
      else if (tok = tryPattern(rxComment, s, i)) {
          cmds.push(["comment", tok[0][1]]);
      }
      else if (tok = tryPattern(rxMacroDef, s, i)) {
          cmds.push(["defmacro", tok[0][1], tok[0][2]]);
          MACROS[tok[0][1]] <- tok[0][2];
      }
      else if (tok = tryPattern(rxMacroCall, s, i)) {
          if (tok[0][1] in MACROS) {
              local macrotext = MACROS[tok[0][1]];
              cmds.push(["callmacro", tok[0][1], macrotext]);
                parseMML(macrotext, function(icmds) { 
                   foreach(i,v in icmds) {
                       cmds.push(v);
                   }
                   cmds.push(["endmacro", tok[0][1]]);
                   parseMML(s, cb, tok[1], cmds);
                });
                return;
          }
      }
      else if (tok = tryPattern(rxInclude, s, i)) {
          local sng = tok[0][1];
          
            if (sng in partials) {
                server.log("restore partial: "+ sng);
                local icmds = partials[sng][0]
               cmds.push(["inc", sng, partials[sng][1]]);
               foreach(i,v in icmds) {
                   cmds.push(v);
               }
               cmds.push(["endinc", sng]);
               parseMML(s, cb, tok[1], cmds);
            
            }
            else {
                server.log("fetch partial: " + sng);
                firebase.read(SONG_ROOT+"/" + sng, function(data) {
                    local state = sng;
                    if (data) { //if song found, use the data instead
                        server.log("got partial: " + data);
                        state = data;
                        parseMML(state, function(icmds) { 
                           partials[sng] <- [icmds,state];
                           cmds.push(["inc", sng,state]);
                           foreach(i,v in icmds) {
                               cmds.push(v);
                           }
                           cmds.push(["endinc", sng]);
                           parseMML(s, cb, tok[1], cmds);
                        });
                    }
                    else {
                   parseMML(s, cb, tok[1], cmds);
                    }
                }, function() {
                   parseMML(s, cb, tok[1], cmds);
                });
            }
            
        return;
          
      }
      else if (tok = tryPattern(rxWhite, s, i)) {
          //ignore whitespace
      }
      else {
          cmds.push(["err", i, s.slice(i,i+1)]);
          cb(cmds);
          return;
      }
    
      if (tok) {
        i = tok[1];
      }
  }
  cb(cmds);
}


function parseCmds(chans) {
    local evs = [];
    local ppqn = 96 * 4;
    foreach (chan, cmds in chans) {
        local loopStack = [];
        local loopI = -1;
        local noteIsOn = false;
        local curNote = -1;
        local curNoteStart = -1.0;
        local curNoteGate = 0;
        local curOctave = 5;
        local curLen = 8;
        local curGate = 0;
        local t = 0.0;
        local ei = 0;
        local i = 0;
        while (i < cmds.len()) {
            local cmd = cmds[i];
            local c = cmd[0];
            if (c == "note" || c == "repeat") {
                if (noteIsOn) {
                    noteIsOn = false;
                    local noteLen = t - curNoteStart;
                    noteLen *= (1.0 - (curNoteGate.tofloat() / 10.0))
                    if ((curNoteStart + noteLen) < t) {
                      evs.push([curNoteStart + noteLen, ei++, ["noteoff", chan]]);
                    }
                }

                local nn = -1;
                if (c == "repeat") {
                    nn = curNote;
                } else {

                 nn = cmd[1] + (12 * (curOctave));
                }
                if (nn >= 0 && nn <= 127) {
                    noteIsOn = true;
                    curNote = nn;
                    curNoteStart = t;
                    curNoteGate = curGate;
                    evs.push([t, ei++, ["noteon", chan, nn]])
                    t += (1.0 / curLen.tofloat())
                }
            }
            else if (c == "extend") {
                t += (1.0 / curLen.tofloat());
            }
            else if (c == "rest") {
                if (noteIsOn) {
                    noteIsOn = false;
                    local noteLen = t - curNoteStart;
                    noteLen *= (1.0 - (curNoteGate.tofloat() / 10.0))
                    evs.push([curNoteStart + noteLen, ei++, ["noteoff", chan]]);
                }
                
                t += (1.0 / curLen.tofloat());
            }
            else if (c == "len") {
                curLen = cmd[1];
            }
            else if (c == "oct") {
                curOctave = cmd[1];
            }
            else if (c == "octup") {
                curOctave += cmd[1];
            }
            else if (c == "octdn") {
                curOctave -= cmd[1];
            }
            else if (c == "tuneup") {
                evs.push([t, ei++, ["tune", chan, cmd[1]]]);
            }
            else if (c == "tunedn") {
                evs.push([t, ei++, ["tune", chan, 0-cmd[1]]]);
            }
            else if (c == "duty") {
                evs.push([t, ei++, ["duty", chan, cmd[1]]]);
            }
            else if (c == "gate") {
                curGate = cmd[1];
            }
            else if (c == "tempo") {
                evs.push([t, ei++, ["tempo", cmd[1]]]);
            }
            else if (c == "lpstart") {
                loopI++;
                loopStack.push([i,1,-1,-1])
            }
            else if (c == "lpend") {
                if (loopI < 0) break; //invalid
                loopStack[loopI][2] = cmd[1];
                loopStack[loopI][3] = i;
                if (loopStack[loopI][1] < loopStack[loopI][2]) {
                    i = loopStack[loopI][0];
                    loopStack[loopI][1]++;
                }
                else {
                    loopI--;
                    loopStack.pop();
                }
            }
            else if (c == "lpcoda") { 
                if (loopI < 0) break; //invalid
                if (loopStack[loopI][2] > -1 && loopStack[loopI][1] >= loopStack[loopI][2]) {
                    i = loopStack[loopI][3];
                    loopI--;
                    loopStack.pop();
                }
            }
            // ignore other commands
            i++;
        }

        if (noteIsOn) {
            noteIsOn = false;
            local noteLen = t - curNoteStart;
            noteLen *= (1.0 - (curNoteGate.tofloat() / 10.0))
            evs.push([curNoteStart + noteLen, ei++, ["noteoff", chan]]);
        }


    }
    evs = evs.map(function (e) {
       return [(ppqn.tofloat()*e[0]).tointeger(), e[1], e[2]]; 
    });
    evs.sort(function (a,b) { 
        return (a[0]*1000 + a[1]) <=> (b[0]*1000 + b[1]);
    });
    local evo = []
    local lt = 0;
    foreach(i,e in evs) {
        evo.push([e[0]-lt, e[2]]);
        lt = e[0];
    }
    return evo;
}

function parseEvents(evs) {
    local data = blob(128);
    foreach(i,e in evs) {
        data.writen(e[0],'w');
        local ev = e[1];
        if (ev[0] == "noteon") {
            data.writen(0x90 + ev[1], 'b');
            data.writen(ev[2], 'b');
        }
        else if (ev[0] == "noteoff") {
            data.writen(0x80 + ev[1], 'b');
        }
        else if (ev[0] == "duty") { 
            data.writen(0xC0 + ev[1], 'b');
            data.writen(ev[2], 'b');
        }
        else if (ev[0] == "tune") { 
            data.writen(0xE0 + ev[1], 'b');
            data.writen(ev[2], 'b');
        }
        else if (ev[0] == "tempo") {
            data.writen(0xF3, 'b');
            data.writen(ev[1], 'w');
        }
    }
    return data;
}

function parseMMLs(lines, cb, i=0, res=[]) {
   if (i < lines.len()) {
       local cmds = []
       cmds.push(["trk",lines[i]]);
       parseMML(lines[i], function(cmds) {
         cmds.push(["endtrk"]);
         res.push(cmds);
         i++;
         parseMMLs(lines, cb, i, res);
       }, 0, cmds);
   }
   else {
       cb(res);
   }
}

firebase <- Firebase(FIREBASE_URL, null);


// Song text handler
function handleState(songtext, callback) {
    // if (songtext.len() < 32) {
    //         server.log("fetch song: " + songtext);
    //     firebase.read(SONG_ROOT+"/" + songtext, function(data) {
    //         local state = songtext;
    //         if (data) { //if song found, use the data instead
    //             server.log("got song: " + data);
    //             state = data;
    //         }
    //         local cmds = parseMMLs(split(state,"|"), callback);
    //     }, function() {
    //         local cmds = parseMMLs(split(songtext,"|"), callback);
    //     });
    // }
    // else {
    MACROS = {}
        server.log("raw song: " + songtext);
        local cmds = parseMMLs(split(songtext,"|"), callback);
    // }
}



function httpHandler(request, response) {
   firebase.read(SONG_ROOT, function(songlist) {
       local allsongs = []
       foreach (k, v in songlist) {
           allsongs.push(k);
       }
       allsongs.sort(function(a,b) { return a <=> b; });
      if ("getsong" in request.query) {
        local songname = strip(request.query.getsong);
        if (songname in songlist) {
          response.send(200, http.jsonencode({ mml=songlist[songname] }));
        }
        else {
          response.send(200, http.jsonencode({ mml="" }));
        }
      }
      else if ("savesong" in request.query) {
        local songname = strip(request.query.savesong);
        local songtext = strip(request.query.mml);
        firebase.write(SONG_ROOT+"/" + songname, songtext);
        response.send(200, http.jsonencode({ status="ok" }));
      }
      else if ("state" in request.query) {
        
        local songtext = strip(request.query.state);
        local origsong = songtext;
        if (songtext in songlist) {
            songtext = songlist[songtext];
        }
        handleState(songtext, function(cmds) {
            local evs = parseCmds(cmds);
    
    
            local disp2 = evs.map(function (b) {
                return http.jsonencode(b); 
            }).reduce(function(a,b){ 
                return a + "\n" + b; 
            });
            
        
            local data = parseEvents(evs);
    
            local disp = cmds.map(function(a) {
                return a.map(function (b) {
                    return http.jsonencode(b); 
                }).reduce(function(a,b){ 
                    return a + "\n" + b; 
                });
            }).reduce(function(a,b){ 
                return a + "\n------\n\n" + b; 
            });
            

            disp2 = format("%d bytes\n",data.len()) + disp2;

            
            device.send("parse", data);
            buildPage(response, { state=origsong, allsongs=allsongs, tokens=disp, events=disp2 });
            
        });
      }
      else {
            buildPage(response, { allsongs=allsongs, state=DEFAULT_SONG });

      }
   });
}


function buildPage(response, data) {
    local headStart = "<!DOCTYPE html>\n<html>\n<head>\n";
    
    local metaPart = "<meta charset='utf-8'>\n<meta http-equiv='X-UA-Compatible' content='IE=edge'>\n<meta name='viewport' content='width=device-width, initial-scale=1'>";
    
    local titlePart = "<title>IMPLAY</title>\n";
    
    local cssIncludes = [];
    local jsIncludes = [];
    
    cssIncludes.push("//netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap.min.css");
    cssIncludes.push("//netdna.bootstrapcdn.com/bootstrap/3.1.1/css/bootstrap-theme.min.css");
    jsIncludes.push("https://ajax.googleapis.com/ajax/libs/jquery/1.11.0/jquery.min.js");
    jsIncludes.push("//netdna.bootstrapcdn.com/bootstrap/3.1.1/js/bootstrap.min.js");
    jsIncludes.push("https://dl.dropboxusercontent.com/u/4805271/implay/ace.js");
    
    local cssIncludesPart = cssIncludes.map(function (a) { return "<link rel='stylesheet' href='" + a + "'>"; }).reduce(function (a,b) { return a + "\n" + b; });

    local jsIncludesPart = jsIncludes.map(function (a) { return "<script src='"+a+"'></script>"; }).reduce(function (a, b) { return a + "\n" + b; });
    

    local headEnd = "</head>\n";
    
    local header = headStart+metaPart+titlePart+cssIncludesPart+jsIncludesPart+headEnd;
    
    local bodyStart = "<body>\n<div class='container'>";

    local headingPart = "<h1>IMPLAY</h1><hr>\n";
    
    local state = StringReplace(data.state,"<","&lt;");
    
    local selectPart = "<select id='songSelector' class='form-control'>\n";
    
    foreach (i,val in data.allsongs) {
       selectPart += "<option value='"+val+"'>"+val+"</option>\n";
    }
    
    selectPart += "</select>\n<br>\n<button class='btn btn-primary' id='loadButton'>Load Song</button><input type='hidden' id='loadedSongName' value=''/><hr>\n";
    
    local mmlPart = "<form role='form' id='stateForm' action="+http.agenturl()+">\n<div class='form-group'>\n<label for='state'>MML</label>\n<div id='stateEditor' class='form-control'>"+state+"</div>\n<textarea id='state' name='state' style='display: none;'></textarea><p class='help-block'><a href='https://github.com/djbouche/implay2'>Reference</a></p></div>\n<br/>\n<button class='btn btn-primary' id='playButton'>Play Song</button>\n<button class='btn btn-success' id='saveButton'>Save Song</button>\n<hr>\n";

    local tokensPart = "";
    if ("tokens" in data) {
        tokensPart = "<h2>Tokens</h2>\n<textarea class='form-control' rows=10 disabled style='border: none; font-family: monospace'>"+data.tokens+"</textarea>\n<hr>\n"
    }

    local eventsPart = "";
    if ("events" in data) {
        eventsPart = "<h2>Events</h2>\n<textarea class='form-control' rows=10 disabled style='border: none; font-family: monospace'>"+data.events+"</textarea>\n<hr>\n"        
    }
    
    local modalsPart = "<div id='confirmSaveModal' class='modal fade'>\n<div class='modal-dialog'>\n<div class='modal-content'>\n<div class='modal-header'>\n<button type='button' class='close' data-dismiss='modal' aria-hidden='true'>&times;</button>\n<h4 class='modal-title'>Save Song</h4>\n</div>\n<div class='modal-body'>\n<form role='form'>\n<div class='form-group'>\n<label for='newSongName'>Song Name</label>\n<input id='newSongName' class='form-control' type='text' value='' placeholder='Enter song name'/>\n</div>\n</div>\n<div class='modal-footer'>\n<button type='button' class='btn btn-default' data-dismiss='modal'>Cancel</button>\n<button type='button' id='confirmSaveButton' class='btn btn-success'>Save Song</button>\n</div>\n</div><!-- /.modal-content -->\n</div><!-- /.modal-dialog -->\n</div><!-- /.modal -->\n";

    local customJs = "";
    
    customJs += "var editor = ace.edit('stateEditor');\neditor.setTheme('ace/theme/monokai');\neditor.setOption('minLines', 15);\neditor.setOption('maxLines', 40);\neditor.getSession().setMode('ace/mode/implay');\n";
    
    customJs += "$('#loadButton').on('click', function (ev) { ev.preventDefault(); var songName = $('#songSelector').val(); $.ajax({ url: '#', data: { getsong: songName }, success: function (data) { $('#loadedSongName').val(songName); editor.setValue(data.mml); }, dataType: 'json'}); });\n"

    customJs += "$('#playButton').on('click', function (ev) { ev.preventDefault(); $('#state').val(editor.getValue()); $('#stateForm').submit(); });\n";

    customJs += "$('#saveButton').on('click', function (ev) { ev.preventDefault(); $('#newSongName').val($('#loadedSongName').val()); $('#confirmSaveModal').modal(); $('#confirmSaveModal').modal('show'); });\n";

    customJs += "$('#confirmSaveButton').on('click', function (ev) { ev.preventDefault(); var songText = editor.getValue(); var songName = $('#newSongName').val(); $.ajax({ url: '#', data: { savesong: songName, mml: songText }, success: function (data) { $('#loadedSongName').val(songName); $('#confirmSaveModal').modal('hide'); }, dataType: 'json'}); });\n";
    
    local customJsPart = "<script>\n"+customJs+"\n</script>\n";
    
    local bodyEnd = "</div></body>\n</html>";

    local body = bodyStart+headingPart+selectPart+mmlPart+tokensPart+eventsPart+modalsPart+customJsPart+bodyEnd;
    
    local pageHTML = header + body;
    
    response.send(200,pageHTML);
}


http.onrequest(httpHandler);


server.log("Agent online and listening");
