## Music Syntax

The syntax is a very simplified derivative of [MML](http://en.wikipedia.org/wiki/Music_Macro_Language).

### Basic Commands

* Notes are any letter from a to g `abcdefg`
* To make a note sharp (+1 half-step or semitone) add a `+` or `s` (eg C# is `c+` or `cs`)
* `/` rest note
* `.` extends the previous note
* `,` acts as a musical dot (e.g., `l8c.` is a dotted eigth note C)
* `\` repeats the previously played note (applied after transpose)
* `l<length>` sets note length division. Defaults to 8
  `l4` is quarter note, `l8` is eigth note, `l16` sixteenth, etc.
* `>` increases current octave by 1.  You can increase by more than one by using `>n` where n is the number of octaves.
* `<` decreases current octave by 1.  You can decrease by more than one by using `<n` where n is the number of octaves.

#### Example

`l8 edcdeee/ddd/egg/ edcdeeeedded l4 c`

### More commands

* `o<octave>` sets octave (1 to 7). Defaults to 5
* `t<tempo>` sets tempo in BPM (32 to 255). Defaults to 120
* `m<factor>` sets gate time, which makes the note length: length \* (1 - (factor * 0.1)). 
  Larger values give shorter stacatto notes. Defaults to 1.
* `p<duty>` sets pulse duty to `<duty>` * 0.1.
  `p5` is a square wave. Defaults to 5.
* `x<tune>` tunes the channel by adding `<tune>`Hz to every note. Defaults to 0.
* `y<semitones>` transposes the channel by `<semitones>` semitones, prefix with `-` for negative numbers. Defaults to 0.
* `y++` `y--` `y+=<semitones>` `y-=<semitones>` increments/decrements the current transpose value.
* `#<comment>` is a comment that will be ignored.

### Multi-channel

* Tempo is set globally but length, octave, gate, duty, and tune are all channel independent.
* `|` Use this to separate tracks (will send commands to different piezos)

#### Example

Sends a C major chords to four piezos

`c|e|g|>c`

### Flow control

* `[ <MML...> ]<n>` defines a loop that will play the inner MML `<n>` times.  
* `[ <MML A...> : <MML B...> ]<n>` defines a loop that will play the inner MML A and MML B `<n>` times, but on the final loop, MML B will be skipped.
* `@<macroname>{ <MML...> }` defines a macro named `<macroname>` with the MML contents inside the braces `{` `}`.  Macros are global across all channels, and definitions are read in order of apperance.
* `@<macroname>` calls previously defined macro, inserting it's contents.
* `$<songname>` imports `<songname>` from Firebase into the channel (thus, only single channel songs work here)
