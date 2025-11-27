
## https://strudel.cc/learn/factories/#catcat
The given items are concatenated, where each one takes one cycle.
- items (any): The items to concatenate

## https://strudel.cc/learn/factories/#seqseq
Like cat, but the items are crammed into one cycle.

## https://strudel.cc/learn/factories/#stackstack
The given items are played at the same time at the same length.

## https://strudel.cc/learn/factories/#stepcatstepcat
'Concatenates' patterns like fastcat, but proportional to a number of steps per cycle.

## https://strudel.cc/learn/factories/#arrangearrange
Allows to arrange multiple patterns together over multiple cycles.

## https://strudel.cc/learn/factories/#polymeterpolymeter
Aligns the steps of the patterns, creating polymeters.

## https://strudel.cc/learn/factories/#silencesilence
Does absolutely nothing..

## https://strudel.cc/learn/factories/#runrun
A discrete pattern of numbers from 0 to n-1

## https://strudel.cc/learn/factories/#binarybinary
Creates a pattern from a binary number.
- n (number): input number to convert to binary

## https://strudel.cc/learn/factories/#binarynbinaryN
Creates a pattern from a binary number, padded to n bits long.
- n (number): input number to convert to binary
- nBits (number): pattern length, defaults to 16

## https://strudel.cc/learn/time-modifiers/#slowslow
Slow down a pattern over the given number of cycles.
- factor (number|Pattern): slow down factor

## https://strudel.cc/learn/time-modifiers/#fastfast
Speed up a pattern by the given factor.
- factor (number|Pattern): speed up factor

## https://strudel.cc/learn/time-modifiers/#earlyearly
Nudge a pattern to start earlier in time.
- cycles (number|Pattern): number of cycles to nudge left

## https://strudel.cc/learn/time-modifiers/#latelate
Nudge a pattern to start later in time.
- cycles (number|Pattern): number of cycles to nudge right

## https://strudel.cc/learn/time-modifiers/#clip--legatoclip
Multiplies the duration with the given number. Also cuts samples off at the end if they exceed the duration.
- factor (number|Pattern): duration multiplier

## https://strudel.cc/learn/time-modifiers/#euclideuclid
Changes the structure of the pattern to form an Euclidean rhythm.
- pulses (number): the number of onsets/beats
- steps (number): the number of steps to fill

## https://strudel.cc/learn/time-modifiers/#euclidroteuclidRot
Like euclid, but has an additional parameter for 'rotating' the resulting sequence.
- pulses (number): the number of onsets/beats
- steps (number): the number of steps to fill
- rotation (number): offset in steps

## https://strudel.cc/learn/time-modifiers/#euclidlegatoeuclidLegato
Similar to euclid, but each pulse is held until the next pulse, so there will be no gaps.

## https://strudel.cc/learn/time-modifiers/#revrev
Reverse all haps in a pattern

## https://strudel.cc/learn/time-modifiers/#palindromepalindrome
Applies rev to a pattern every other cycle.

## https://strudel.cc/learn/time-modifiers/#iteriter
Divides a pattern into a given number of subdivisions, plays the subdivisions in order, but increments the starting subdivision each cycle.

## https://strudel.cc/learn/time-modifiers/#iterbackiterBack
Like iter, but plays the subdivisions in reverse order.

## https://strudel.cc/learn/time-modifiers/#plyply
The ply function repeats each event the given number of times.

## https://strudel.cc/learn/time-modifiers/#segmentsegment
Samples the pattern at a rate of n events per cycle.
- segments (number): number of segments per cycle

## https://strudel.cc/learn/time-modifiers/#compresscompress
Compress each cycle into the given timespan, leaving a gap

## https://strudel.cc/learn/time-modifiers/#zoomzoom
Plays a portion of a pattern, specified by the beginning and end of a time span.

## https://strudel.cc/learn/time-modifiers/#lingerlinger
Selects the given fraction of the pattern and repeats that part to fill the remainder of the cycle.
- fraction (number): fraction to select

## https://strudel.cc/learn/time-modifiers/#fastgapfastGap
speeds up a pattern like fast, but rather than it playing multiple times as fast would it instead leaves a gap.

## https://strudel.cc/learn/time-modifiers/#insideinside
Carries out an operation 'inside' a cycle.

## https://strudel.cc/learn/time-modifiers/#outsideoutside
Carries out an operation 'outside' a cycle.

## https://strudel.cc/learn/time-modifiers/#cpmcpm
Plays the pattern at the given cycles per minute.

## https://strudel.cc/learn/time-modifiers/#ribbonribbon
Loops the pattern inside an offset for cycles.
- offset (number): start point of loop in cycles
- cycles (number): loop length in cycles

## https://strudel.cc/learn/time-modifiers/#swingbyswingBy
Delays events in the second half of each slice by the amount x.
- subdivision (number): slice size
- offset (number): delay amount

## https://strudel.cc/learn/time-modifiers/#swingswing
Shorthand for swingBy with 1/3.

## https://strudel.cc/functions/value-modifiers/#addadd
Adds the given number to each item in the pattern.

## https://strudel.cc/functions/value-modifiers/#subsub
Like add, but the given numbers are subtracted.

## https://strudel.cc/functions/value-modifiers/#mulmul
Multiplies each number by the given factor.

## https://strudel.cc/functions/value-modifiers/#divdiv
Divides each number by the given factor.

## https://strudel.cc/functions/value-modifiers/#roundround
Returns a new pattern with all values rounded to the nearest integer.

## https://strudel.cc/functions/value-modifiers/#floorfloor
Returns a new pattern with all values set to their mathematical floor.

## https://strudel.cc/functions/value-modifiers/#ceilceil
Returns a new pattern with all values set to their mathematical ceiling.

## https://strudel.cc/functions/value-modifiers/#rangerange
Returns a new pattern with values scaled to the given min/max range (from 0..1).

## https://strudel.cc/functions/value-modifiers/#rangexrangex
Returns a new pattern with values scaled to the given min/max range, following an exponential curve.

## https://strudel.cc/functions/value-modifiers/#range2range2
Returns a new pattern with values scaled to the given min/max range (from -1..1).

## https://strudel.cc/functions/value-modifiers/#ratioratio
Allows dividing numbers via list notation using ":".

## https://strudel.cc/functions/value-modifiers/#asas
Sets properties in a batch.
- mapping (String|Array): the control names that are set

## https://strudel.cc/learn/samples/#beginbegin
Skips the beginning of each sample.
- amount (number|Pattern): between 0 and 1

## https://strudel.cc/learn/samples/#endend
Cuts off the end off each sample.
- length (number|Pattern): 1 = whole sample

## https://strudel.cc/learn/samples/#looploop
Loops the sample.
- on (number|Pattern): If 1, the sample is looped

## https://strudel.cc/learn/samples/#loopbeginloopBegin
Begin to loop at a specific point in the sample.
- time (number|Pattern): between 0 and 1

## https://strudel.cc/learn/samples/#loopendloopEnd
End the looping section at a specific point in the sample.
- time (number|Pattern): between 0 and 1

## https://strudel.cc/learn/samples/#cutcut
Cut will stop a playing sample as soon as another samples with in same cutgroup is to be played.
- group (number|Pattern): cut group number

## https://strudel.cc/learn/samples/#loopatloopAt
Makes the sample fit the given number of cycles by changing the speed.

## https://strudel.cc/learn/samples/#fitfit
Makes the sample fit its event duration.

## https://strudel.cc/learn/samples/#chopchop
Cuts each sample into the given number of parts.

## https://strudel.cc/learn/samples/#striatestriate
Cuts each sample into the given number of parts, triggering progressive portions.

## https://strudel.cc/learn/samples/#sliceslice
Chops samples into the given number of slices, triggering those slices with a given pattern.

## https://strudel.cc/learn/samples/#splicesplice
Works the same as slice, but changes the playback speed of each slice.

## https://strudel.cc/learn/samples/#scrubscrub
Allows you to scrub an audio file like a tape loop.

## https://strudel.cc/learn/samples/#speedspeed
Changes the speed of sample playback.
- speed (number|Pattern): playback speed

## https://strudel.cc/learn/synths/#basic-waveformsBasic Waveforms
s, sound
Selects the sound/synth to use.
- sound (string): sine, sawtooth, square, triangle, or sample name

## https://strudel.cc/learn/synths/#noiseNoise
noise
Adds noise to the sound.
- amount (number): noise amount

## https://strudel.cc/learn/synths/#vibvib
vibrato, v, vib
Applies a vibrato to the frequency of the oscillator.
- frequency (number|Pattern): of the vibrato in hertz

## https://strudel.cc/learn/synths/#vibmodvibmod
vmod
Sets the vibrato depth in semitones.
- depth (number|Pattern): of vibrato (in semitones)

## https://strudel.cc/learn/synths/#fmfm
fmi
Sets the Frequency Modulation of the synth.
- brightness (number|Pattern): modulation index

## https://strudel.cc/learn/synths/#fmhfmh
Sets the Frequency Modulation Harmonicity Ratio.
- harmonicity (number|Pattern): ratio

## https://strudel.cc/learn/synths/#fmattackfmattack
Attack time for the FM envelope.
- time (number|Pattern): attack time

## https://strudel.cc/learn/synths/#fmdecayfmdecay
Decay time for the FM envelope.
- time (number|Pattern): decay time

## https://strudel.cc/learn/synths/#fmsustainfmsustain
Sustain level for the FM envelope.
- level (number|Pattern): sustain level

## https://strudel.cc/learn/synths/#fmenvfmenv
Ramp type of fm envelope.
- type (number|Pattern): lin | exp

## note
note
Sets the note to play.
- note (string|number): note name or midi number

## gain
gain
Sets the volume of the sound.
- amount (number): volume (0..1 usually)

## cutoff
cutoff
Sets the filter cutoff frequency.
- frequency (number): cutoff in Hz
