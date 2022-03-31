# TDT Windowed Buffering
Buffer sorted spikes or LFPs during a trial on the TDT system (RZ2). Then transfer data to the ARCADE PC. Buffering is time locked to an event _e.g._ stimulus onset. To compute PSTHs, tuning curves, power spectra, etc. online, between trials.

Buffers are circular. Once they fill up, the index loops back to the beginning for a fresh sweep of data. This can be exploited when data is regularly sampled, as with the LFP buffer, to define a buffer window of a certain length. Since spikes occur irregularly, a large buffer should be used so as not to miss data.

Once an event of interest triggers a strobe input to the buffer, the buffer then counts down for the duration of a response window. Buffering stops once the end of the response window is reached. Data then sits in the buffer until it can be retrieved. Buffering is only resumed once an explicit signal is provided.

## Synapse User Gizmos
These are TDT circuit files that can be edited with RPvdsEx. They can be loaded into Synapse as Custom Gizmos if they are placed in _e.g._ `C:\TDT\Synapse\UserCircuits`

### MCSimEphys.rcx
Generates 4 to 32 channels of wideband, signals that simulate extracellular recordings. For example, from a cross-laminar probe in visual cortex. Each channel is generated independently of the others. The signal on a given channel is the sum of Guaussian noise, a sinusoid, and a Poisson spike train of action potential waveforms.

Parameters including the noise and LFP amplitude, LFP frequency and phase, spike rate, and modulation of spike rate by LFP phase can all be set from the ARCADE PC using SynapaseAPI commands.

### MCSpkWinBuf.rcx
Spike windowed buffering for 9 or more electrophysiology channels.

SortCodes samples will contain only zeros if no spike was detected. MCSpkWinBuf only buffers a SortCode sample if at least once channel contains a spike. Hence, samples are buffered at irregular times. In order to know when spikes were samples, secondary buffers are used to store time stamps for every buffered SortCode sample. In addition, the strobe event is time-stamped so that buffered spike times can be zeroed on the event of interest.

### SortCodes4C.rcx
If ephys channel count is 1 to 8 then the spike sort Gizmos will output SortCodes with a channel count of 2. MC Gizmos and Components require a count of 4. This 'zero-pads' the 2 channel SortCodes with an additional 2 channels of zeros. It outputs a SortCodes00 with channel count 4 that can feed directly to MCSpkWinBuf.

### MCLfpWinBuf.rcx
LFP windowed buffering for 9 or more electrophysiology channels. LFP and their time stamps are sampled continuously at approximately 1000Hz. The strobe event is also time stamped so that LFP signals can be zeroed on that event.

### WinBuf gizmoControls.txt
To maintain existing windowed buffers, and to guide the creation of new ones, this document describes the required set of Gizmo controls, and the spelling of their names. If this convention is strictly adhered to, then the same code can be used on the ARCADE PC to control and read data from any windowed buffer running on the TDT system.

### Test_MCSpkWinBuf.synexpz
An example Synapse experiment. This can be used with MCSpkWinBuf_test.m (see below) to test both the MCSpkWinBuf and MCLfpWinBuf Gizmos.

## MATLAB code for ARCADE PC

### TdtWinBuf.m
MATLAB class definition. Allows access via SynapseAPI to windowed buffer Gizmos running on the TDT system. It is intended to function with all variants of the windowed buffer Gizmos, thus requiring them to have a standardised interface. This class helps with setting buffer size and response window width by automatically converting from seconds to samples. It also reads in buffered data and applies whatever data type conversion and decompression is necessary.

### MCSpkWinBuf_test.m
For testing the MCSpkWinBuf and MCLfpWinBuf Gizmos. This requires the MCSimEphys Gizmo. It tells the MCSimEphys Gizmo when to modulate firing rates and LFPs, such that a transient response to an event is generated with increasing latency across channels. Requires latest copy of ARCADE (see below).

### MCSpkWinBuf_test_example.pdf
An example of the output that should be produced by running Test_MCSpkWinBuf.synexpz and MCSpkWinBuf_test.m together.

## Appendix

### ARCADE
The latest version of ARCADE is available here, https://github.com/esi-neuroscience/ARCADE.git

### SortCodes format.
Synapse spike sorter Gizmo (Box Sort or PCA Sort) accepts raw electrophysiology signals (_e.g._ from a PZ2) as input. Call the input channel count Nin. Spike sorting results are compressed into a 32-bit integer format and sent to the SortCodes output. Each individual sample of SortCodes has a channel count of Nout = 2 * ceil( Nin / 8 ). If this set of 32-bit integers is treated as unsigned, and broken up into a string of unsigned 8-bit integers (bytes), then the ith byte contains results from the ith input channel. MATLAB typecast( <32-bit integers> , 'uint8' ) will breat SortCodes output into a string of bytes.

### Why 9 or more ephys channels needed for MC*WinBuf.rcx?
This is because Synapse spike sorter Gizmos only generate an output channel count in SortCodes of 4 or higher if they receive a channel count of 9 or higher as input. The multi-channel circuit file components that are used by the MC*WinBuf.rcx buffers require a minimum channel count of 4.

### Time stamps
The windowed buffers maintain their own internal timers. A unique time stamp is assigned to every sample that is processed by the parent device (_e.g._ RZ2 at ~25kHz). Due to problems with numerical overflow and the peculiarities of circuit file counter components, each time stamp must be represented by a pair of 32-bit integers. In analogy with the minutes and seconds used to measure the time of day, each time stamp consists of one _Minute_ and one _Second_. A _Second_ has the period of one sample (at ~25kHz, ~40micro-seconds), and one _Second_ is counted for each and every sample. The _Seconds_ counter has a range of 0 to 999,998. Once the 999,999th _Second_ is counted, then the _Seconds_ counter is reset to 0, and the _Minutes_ counter increases by +1. Hence, there are 999,999 _Seconds_ per _Minute_. A single time stamp (_Minute_,_Second_) is converted to number of samples by Samples = 999999*_Minute_ + _Second_. Samples divided by the sampling rate converts each time stamp into SI seconds.
