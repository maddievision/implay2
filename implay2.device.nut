/***************************************************************************
 * IMPLAY
 * Andrew Lim & Bunnie Curtis
 * 2013-12-07 v1
 * 2014-05-28 v2
 *
 * Device Code
 *
 ***************************************************************************/

CMD_END <- 0
CMD_NOTE <- 1
CMD_REPEAT <- 2
CMD_EXTEND <- 3
CMD_REST <- 4
CMD_LEN <- 5
CMD_OCT <- 6
CMD_OCTUP <- 7
CMD_OCTDN <- 8
CMD_DUTY <- 9
CMD_GATE <- 10
CMD_TEMPO <- 11
CMD_LPSTART <- 12
CMD_LPCODA <- 13
CMD_LPEND <- 14

NOTES <- [33,35,37,39,41,44,46,49,52,55,58,62,65,69,73,78,82,87,93,98,104,110,117,123,131,139,147,156,165,175,185,196,208,220,233,247,262,277,294,311,330,349,370,392,415,440,466,494,523,554,587,622,659,698,740,784,831,880,932,988,1047,1109,1175,1245,1319,1397,1480,1568,1661,1760,1865,1976,2093,2217,2349,2489,2637,2794,2960,3136,3322,3520,3729,3951,4186,4435,4699,4978,0];

piezo_pins <- [hardware.pin5, hardware.pin7, hardware.pin8, hardware.pin2];
led <- hardware.pin9;
led.configure(DIGITAL_OUT_OD);
led.write(1);

function midiNoteToFreq(num) {
//   return 440.0 * math.pow(2.0,(num-69.0)/12.0);
     return NOTES[num];
}

noteCount <- 0;

class Tone {
    pin = null;
    playing = null;
    wakeup = null;
    channel = null;
    duty = null;
    tune = null;

    constructor(_pin,_channel) {
        this.pin = _pin;
        this.channel = _channel;
        this.playing = false;
        this.duty = 0.5;
        this.tune = 0;
    }
    
    function isPlaying() {
        return playing;
    }
    
    function setDuty(newDuty) {
        duty = newDuty;
    }

    function setTune(newTune) {
        tune = newTune;
    }

        
    function noteOn(num) {
        noteCount = noteCount | (1 << channel);
        led.write(0);
        pin.configure(PWM_OUT, 1.0/(tune+midiNoteToFreq(num)), duty);
        playing = true;
    }
    
    function noteOff() {
        noteCount = noteCount & ~(1 << channel);
        if (noteCount == 0) {
          led.write(1);
        }
        pin.write(0.0);
        playing = false;
    }
}

function setupPiezo() {
    piezo <- [];
    for (local i = 0; i < piezo_pins.len(); i += 1) { 
        piezo.push(Tone(piezo_pins[i],i));
    }
    server.log("Piezo channels: "+piezo.len());
}

setupPiezo();

curtempo <- 120;
cursong <- blob(0);
playindex <- 0;

function startpn(song) {
    cursong = song;
    playindex = 0;
    curtempo = 120;
    foreach (i,p in piezo) {
        p.noteOff();
        p.setDuty(0.5);
        p.setTune(0);
    }
    pn();
}

function pn() {
  try {
        if (!cursong.eos() && cursong.tell() < cursong.len()) {
          local delta = cursong.readn('w');
          if (delta == 0) {
              runevent();
          }
          else {
              local w = delta.tofloat() * ((60.0/curtempo.tofloat())/96.0);
              imp.wakeup(w, runevent);
          }
        }
  }
  catch (e) {
     foreach (i,p in piezo) {
         p.noteOff();
     }
  }
}
DUTY_MAP <- [0.1, 0.125, 0.25, 0.3, 0.4, 0.5, 0.6, 0.75, 0.875, 0.9, 0.95];

function runevent() {
  if (!cursong.eos() && cursong.tell() < cursong.len()) { 
      local cmd = cursong.readn('b');
      if (cmd == 0xF3) {
          curtempo = cursong.readn('w');
      }
      else if (cmd >= 0x80 && cmd <= 0x8F) {
        local chan = cmd - 0x80;
        piezo[chan].noteOff();
      }
      else if (cmd >= 0x90 && cmd <= 0x9F) {
        local chan = cmd - 0x90;
        local note = cursong.readn('b');
        piezo[chan].noteOn(note);
      }
      else if (cmd >= 0xC0 && cmd <= 0xCF) {
        local chan = cmd - 0xC0;
        local duty = cursong.readn('b');
        piezo[chan].setDuty(DUTY_MAP[duty]);
      }
      else if (cmd >= 0xE0 && cmd <= 0xEF) {
        local chan = cmd - 0xE0;
        local tune = cursong.readn('b');
        piezo[chan].setTune(tune);
      }
      pn();
  }
}

function parse(b) {
  server.log(format("Received song: %d bytes",b.len()));
  startpn(b);
}

server.log("Device listening for songs");

agent.on("parse",parse);