
% 
% Test the custom MCSpkWinBuf Gizmo, in combination with the MCSimEphys
% Gizmo.
% 
% Written by Jackson Smith - March 2022 - Fries Lab (ESI Frankfurt)
% 

%% -- CONSTANTS -- %%

% Network name of system upon which Synapse is running
C.server = 'ESI-WSFRI026' ;

% Input integer type, 32-bit unsigned integer, in TDT parlance, a 'word'.
C.int.word = 'uint32' ;

% Break up into bytes of this type, 8-bit unsigned integer
C.int.byte = 'uint8' ;

% Number of ephys channels per integer
C.int.EchansPerWord = 4 ;

% Expected names of the simulator and buffer gizmos
C.gizmo.sim.nam = 'MCSimEphys1' ;
C.gizmo.bspk.nam = 'MCSpkWinBuf1' ;
C.gizmo.blfp.nam = 'MCLfpWinBuf1' ;

% All required Gizmos
C.gizmo.nam = { C.gizmo.sim.nam , C.gizmo.bspk.nam , C.gizmo.blfp.nam } ;

%--- Simulation parameters ---%

  % Spike rates, in spk/sec
  C.rate.rest =   1 ;
  C.rate.base =   5 ;
  C.rate.resp = 200 ;

  % Buffer window parameters, in seconds. C.win.resp will be determined
  % during simulation. This is a placeholder value.
  C.win.base = 0.5 ;
  C.win.resp = 2.0 ;
  
  % Duration of response
  C.dur.latency = 0.05 ;
  C.dur.resp    = 0.30 ;

% Colour of raster plots for increasing sort code values
C.colord = [ 0.000 , 0.447 , 0.741 ;
             0.850 , 0.325 , 0.098 ;
             0.929 , 0.694 , 0.125 ;
             0.494 , 0.184 , 0.556 ;
             0.466 , 0.674 , 0.188 ;
             0.301 , 0.745 , 0.933 ;
             0.635 , 0.078 , 0.184 ] ;

% Variables to keep
C.keep = { 'C' , 'D' } ;
  
  
%% -- Connect to SynapseAPI -- %%

% SynapseAPI not opened yet, or it was closed. If it is open then don't
% bother implicitly destroying existing SynapseAPI object just to make a
% new one.
if  ~ isfield( C , 'syn' )  ||  ~ isvalid( C.syn )
  C.syn = SynapseAPI( C.server ) ;
end

% Gizmos names
nam = C.syn.getGizmoNames ;

% Look for our Gizmos
i = ismember( C.gizmo.nam , nam ) ;

  % Something's missing, tell user
  if  ~ all( i )
    
    error( 'Synapse session lacks Gizmo(s): %s' , ...
      strjoin( C.gizmo.nam( ~i ) , ' , ' ) )
    
  end % missing giz

% Gizmos of interest, extract field name and Gizmo name
for  G = { 'sim', 'bspk', 'blfp' } , g = G{ 1 } ; nam = C.gizmo.( g ).nam ;
  
  % Get list of parameter names
  C.gizmo.( g ).par = C.syn.getParameterNames( nam ) ;
  
  % Retrieve parameter information
  C.gizmo.( g ).info = cellfun( @( p ) C.syn.getParameterInfo( nam, p ),...
    C.gizmo.( g ).par , 'UniformOutput' , false ) ;
  
  % Associate parameter names with info structs, a 2 x N par cell array
  C.gizmo.( g ).info = [ C.gizmo.( g ).par , C.gizmo.( g ).info ]' ;
  
  % Construct a struct in which each field is named after a parameter and
  % contains that parameter's info
  C.gizmo.( g ).info = struct( C.gizmo.( g ).info{ : } ) ;
  
end % giz

% All TDT system sampling rates
C.fs = C.syn.getSamplingRates( ) ;

% Get only the sampling rate of the parent to the ephys simulator
C.fs = C.fs.( C.syn.getGizmoParent( C.gizmo.sim.nam ) ) ;

% Get 'Seconds' (i.e. samples at fs) per 'Minute'. Spike time stamps are
% recorded in 'Minutes' and 'Seconds', to avoid rounding error within the
% duration of any acute experiment.
C.SecPerMin = C.gizmo.bspk.info.Seconds.Max ;

% Done
clearvars( '-except' , C.keep{ : } )


%% --- Set up ARCADE DAQ server --- %%

% Can't see DaqServer.m. Add it to the path and open DAQ server.
if  ~ exist( 'DaqServer.m' , 'file' )
  add_arcade_to_path
  !C:\Toolbox\ARCADE\arcade\DaqServer\NidaqServer.exe &
end

% Connect to NidaqServer
DaqServer.Connect( ) ;

% Set all digital input pins to low (off, 0, false)
DaqServer.EventMarker( 0 ) ;


%% --- Run simulation --- %%

% -- Initialisation -- %

% Guarantee that DAQ pins are low, 0, off, false
DaqServer.EventMarker( 0 ) ;

% Check that Synapse is in run-time mode (value 2 or 3, Preview or Record)
if  C.syn.getMode < 2
  
  % Set to Preview mode
  if  ~ C.syn.setMode( 2 ) , error( 'Failed to set mode.' ) , end
  
  % Wait for this to kick in
  while  C.syn.getMode ~= 2 , sleep( 500 ) , end
  
end % mode

% Read number of ephys channels
C.gizmo.sim.ephys = C.syn.getParameterValue( C.gizmo.sim.nam , 'NumChan' );

% Working with ephys simulator
giz = C.gizmo.sim ;

% Determine response on and off times relative to trigger, for each
% channel. First, replicate channel ID; once for response ON, other for
% response OFF (return to baseline).
ev.ch = [ 1 ; 1 ] .* ( 1 : giz.ephys ) ;

% Next, build a table of latencies and determine the cumulative sum of time
% across activations (response on) of each channel, which is ordered
% chronologically by channel ID. Add duration of transient response to each
% of these, in second row.
ev.tim = [ 0 ; C.dur.resp ] + ...
  cumsum( repmat( C.dur.latency , 1 , giz.ephys ) ) ;

% Lastly, note the firing rate we switch to for each channel on each event
ev.spk = repmat( [ C.rate.resp ; C.rate.base ] , 1 , giz.ephys ) ;

% Sort times from earliest to latest, remember mapping from unsorted to
% sorted
[ ev.tim , i ] = sort( ev.tim( : ) ) ;

% Apply the same mapping to channel ID and spike rate. Returns column
% vectors that are all in register with ev.tim.
ev.ch  = ev.ch ( i ) ;
ev.spk = ev.spk( i ) ;

% Compute time between events, replace initial latency on channel 1
ev.dtim = [ C.dur.latency ; diff( ev.tim ) ] ;

% Response window will be the sum of all events following trigger, plus one
% transient response duration
C.win.resp = ev.tim( end ) + C.dur.resp ;

  % At least nchan/10 + resp second response window
  C.win.resp = max( giz.ephys / 10 + C.dur.resp , C.win.resp ) ;

% Response window duration, in samples, rounded down
win = floor( C.win.resp * C.fs ) ;

% Windowed buffers
for  NAM = { C.gizmo.bspk.nam , C.gizmo.blfp.nam } , nam = NAM{ 1 } ;

  % Set response window duration
  setpar( C , nam , 'RespWin' , win , 'set response window duration' )

  % Start buffering signal values: HIGH (ON,1,TRUE), LOW (OFF,0,FALSE)
  for  i = [ 1 , 0 ]

    setpar( C , nam , 'StartBuff' , i , 'resume buffering' )

  end % resume buffering spikes

end % windowed buffers

% Working with ephys simulator
giz = C.gizmo.sim ;
nam = giz.nam ;

% Set LFP phase to 0 deg
setpars( C , nam , 'LfpPhase' , zeros( giz.ephys , 1 ) , 'zero LFP phase' )

% Set baseline firing rates
setpars( C , nam , 'SpkRate' , repmat( C.rate.base , giz.ephys , 1 ) , ...
  'set baseline firing rates' )

% -- Start 'Trial' -- %

% Higher precision Window's media timer requested
timeBEPeriod( 'b' , 1 ) ;

% Wait for duration of baseline window
sleep( 1e3 * C.win.base )

% Trigger windowed buffering, and response window countdown
DaqServer.EventMarker( intmax( 'uint16' ) ) ;

% Mark this time and set it as the time of the last event
trigtic = tic ;
 lastev = trigtic ;

% Events
for  i = 1 : numel( ev.tim )
  
  % Measure difference between deadline and time since trigger
  tim = ev.tim( i ) - toc( trigtic ) ;
  
  % We have not run past this deadline, now - trig < deadline
  if  tim > 0
  
    % Take duration to next event minus time that has elapsed since
    % previous event, producing actual duration until next event. In ms.
    dt = 1e3 * ( ev.dtim( i ) - toc( lastev ) ) ;

    % Wait for that duration. dt < 0 if time has overrun, in which case no
    % waiting.
    sleep( max( 0 , dt ) )
    
  else
    
    fprintf( 'ev %d overrun %0.3fs\n' , i , tim )
  
  end % wait
  
  % Mark time of this event, for reference in timing that which follows
  lastev = tic ;
  
  % Firing rate rising to response level
  if  ev.spk( i ) == C.rate.resp
    
    % ... setting phase to zero
    setpars( C , nam , 'LfpPhase' , 90 , 'LFP phase = 90', ev.ch( i ) - 1 )
    
    % Modulate firing rate by local LFP rhythm
    setpars( C , nam , 'SpkLfpMod' , 1 , 'set LFP-rate modulation' , ... 
      ev.ch( i ) - 1 )
    
  % Decouple spike rate from LFP
  else
    
    setpars( C , nam , 'SpkLfpMod' , 0 , 'set LFP-rate modulation' , ... 
      ev.ch( i ) - 1 )
    
  end % LFP phase
  
  % Modulate firing rate on appropriate channel
  setpars( C, nam, 'SpkRate', ev.spk( i ), 'set response firing rates', ... 
    ev.ch( i ) - 1 )
  
end % events

% Wait for end of response window, subtract total response window time by
% time elapsed since trigger. Floor at zero, in case more time has passed
% than width or response window.
sleep( 1e3 * max( 0 , C.win.resp - toc( trigtic ) ) )

% Return spike rates to some low level
setpars( C , nam , 'SpkRate' , repmat( C.rate.rest , giz.ephys , 1 ) , ...
  'Failed to set inter-trial firing rates.' )

% Set LFP phase to 0 deg
setpars( C , nam , 'LfpPhase' , zeros( giz.ephys , 1 ) , 'zero LFP phase' )

% Lower DAQ pins (0, off, false)
DaqServer.EventMarker( 0 ) ;

% Higher precision Window's media timer released
timeBEPeriod( 'e' , 1 ) ;

% -- Read from windowed buffers -- %

% Measure time point before buffer reads
tic ;

% Windowed buffer field names
for  F = { 'bspk' , 'blfp' } , f = F{ 1 } ;
  
  % Point to working copy of gizmo struct. Beware copy-on-write behaviour.
  giz = C.gizmo.( f ) ;
  
  % Get all scalar buffering information
  for  PAR = { 'BuffSize' , 'ChanPerSamp' , 'DownSamp' , 'BitsPerVal' , ...
      'ScaleFactor' , 'CompDomain' , 'BuffSizeMC' , 'RespWin' , ...
        'Mindex' , 'Sindex' , 'MCindex' , 'Counter' , 'EventMin' , ...
          'EventSec' } , par = PAR{ 1 } ;

    giz.( par ) = C.syn.getParameterValue( giz.nam , par );

  end % bspk size

  % Compute number of MC samples after compression
  switch  f
    case  'bspk' , bufsiz = giz.BuffSize ;
    case  'blfp' , bufsiz = giz.BuffSize / 2 ;
  end
  
  % Read in buffered time stamps ...
  giz.Minutes = readbuf( C , giz , giz.Mindex , 'Minutes' , giz.BuffSize );
  giz.Seconds = readbuf( C , giz , giz.Sindex , 'Seconds' , giz.BuffSize );

  % ... and buffered spike SortCodes.
  giz.MCsamples = readbuf( C , giz , giz.MCindex , 'MCsamples' , ...
    giz.BuffSizeMC ) ;

  % Store reads, overide MATLAB's copy-on-write
  C.gizmo.( f ) = giz ;

end % windowed buffers

% Measure time taken to read buffers
fprintf( 'Read buffered spk & LFP from %d chan in %.3fms\n' , ...
  C.gizmo.sim.ephys , 1e3 * toc )

% -- Done -- %

clearvars( '-except' , C.keep{ : } )


%% --- Convert buffered data --- %%

% Windowed buffer field names
for  F = { 'bspk' , 'blfp' } , f = F{ 1 } ; giz = C.gizmo.( f ) ;

  % [ 'Minute' , 'Second' ] time stamps, cast to double, convert to samples
  tim = double( [ giz.Minutes , giz.Seconds ] ) * [ C.SecPerMin ; 1 ] ;

  % Same again for windowing event
   ev = double( [ giz.EventMin , giz.EventSec ] ) * [ C.SecPerMin ; 1 ] ;

  % Zero spike times on windowing event and convert to seconds
  tim = ( tim - ev ) ./ C.fs ;
  
  % Channel count per sample
  N = giz.ChanPerSamp ;
  
  % Point to multi-channel samples
  mc = giz.MCsamples ;
  
  % Decompress data according to compression scheme
  switch  giz.nam
    
    % Spike windowed buffer - Extract sort codes
    case  C.gizmo.bspk.nam
      
      % Bytes are compressed into 32-bit integers. Adjust number of
      % channels, convert unit from number of 32-bit ints to total
      % compression capacity in ephys channels
      N = N * C.int.EchansPerWord ;

      % And then de-compress the data by splitting it into bytes
      mc = typecast( mc , C.int.byte ) ;
      
    % LFP windowed buffer - extract time points
    case  C.gizmo.blfp.nam
      
      % Data is stored as int32, so convert data back to this
      mc = cast( mc , 'int32' ) ;
      
      % Two MC samples packed as pair of int16 into each int32. Extract
      % them.
      mc = typecast( mc , 'int16' ) ;
      
      % Cast to double and then remove scaling factor
      mc = cast( mc , 'double' ) ./ giz.ScaleFactor ;
      
      % Column vector has organisation [samp i [c1 [t,t+1], c2 [t,t+1], ...
      % In which there are two LFP samples in time per channel per MC
      % sample. Reorganise the data into time x channel x MC sample.
      mc = reshape( mc , 2 , N , [ ] ) ;
      
      % Permute this matrix to channel x time x MC sample. It is now ready
      % to be reshaped into time x channels, below.
      mc = permute( mc , [ 2 , 1 , 3 ] ) ;
      
      % Don't forget to decompress the time vector. Add new time stamps.
      tim = tim' - [ 1 / ( C.fs / giz.DownSamp ) ; 0 ] ;
      
      % Convert back into column vector
      tim = tim( : ) ;
      
    otherwise , error( 'Programming error' )
  end % decompress

  % Reshape into spikes/times x channels(bytes)
  mc = reshape( mc , N , [ ] )' ;

    % Sanity check, row count this should equal the number of time stamps
    if  size( mc , 1 ) ~= numel( tim )
      error( '%s: MCsample to timestamp misalignment' , giz.nam )
    end

  % Get rid of empty channel placeholders
  mc( : , C.gizmo.sim.ephys + 1 : end ) = [ ] ;

  % Find any sample that lies outside of baseline or response time windows
  i = tim < -C.win.base | ...
      tim > +C.win.resp ;

  % Discard these samples because we won't plot them anyway
  tim( i ) = [ ] ;
  mc( i , : ) = [ ] ;

  % Pack into a data struct
  D.( f ).time = tim ;
  D.( f ).mc   =  mc ;

end % Win buffers

% Done
clearvars( '-except' , C.keep{ : } )


%% --- Plot buffered spikes --- %%

% Create new figure
fig = figure ;

% Shift fig down, then make taller by one third
fig.Position( 2 ) = fig.Position( 2 ) - fig.Position( 4 ) / 3 ;
fig.Position( 4 ) = fig.Position( 4 ) + fig.Position( 4 ) / 3 ;

% New axes for rasters
ax = subplot( 3 , 1 , 1 : 2 , 'XLim' , [ -C.win.base , +C.win.resp ] , ...
  'YLim' , [ 0 , C.gizmo.sim.ephys ] + 0.5 , 'NextPlot' , 'add' ) ;
     
% Labels
title( 'Windowed spike buffering from TDT' )
ylabel( 'Ephys channels' )

% Channel separators
plot( ax.XLim' , ( 1 + 0.5 : C.gizmo.sim.ephys - 0.5 ) + [ 0 ; 0 ] , ...
  'Color' , [ 0.75 , 0.75 , 0.75 ] )

% Zero line
plot( [ 0 , 0 ], ax.YLim, 'Color', [ 0.75 , 0.75 , 0.75 ], 'LineWidth', 1 )

% Ephys channels
for  c = 1 : C.gizmo.sim.ephys
  
  % Point to LFP time, and signal from this channel
  X = D.blfp.time ;  Y = D.blfp.mc( : , c ) ;
  
  % Scale LFP signal so that it spans the numeric range of the raster
  % ticks, then centre on channel's row
  Y = Y ./ max( abs( Y ) ) .* 0.4  +  c ;
  
  % Show LFP signal
  plot( X , Y , 'Color' , [ 0.6 , 0.6 , 0.6 ] )
  
  % Non-zero sort codes from channel c
  i = D.bspk.mc( : , c ) > 0 ;
  
  % Return only times when sort codes were non-zero, as a row vector
  tim = D.bspk.time( i )' ;
  
  % And again for the sort codes themselves
  sc = D.bspk.mc( i , c )' ;
  
  % No sort codes, onto the next channel
  if  isempty( sc ) , continue , end
  
  % Unique set of sort codes
  USC = unique( sc ) ;
  
  % Initialise lower y-axis position of first tick
  y = c + -0.4 ;
  
  % Length of ticks
  dy = 0.8 / numel( USC ) ;
  
  % Colour index
  col = 1 ;
  
  % Step through all unique sort codes
  for  usc = USC
    
    % Find spikes with this sort code
    i = sc == usc ;
    
    % Return times of these spikes
    X = tim( i ) ;
    
    % Duplicate and add row of NaN values, so that a single line can draw
    % separate ticks in the raster plot. This is now 3 x number of spikes.
    X = [ X ; X ; nan( size( X ) ) ] ;

    % Get y-axis points for a single tick from this channel. 3 x 1.
    Y = [ y + [ 0 ; dy ] ; NaN ] ;

    % Repeat y-axis points for each spike
    Y = repmat( Y , 1 , size( X , 2 ) ) ;

    % Plot spike raster
    plot( X( : ) , Y( : ) , 'Color' , C.colord( col , : ) )
  
    % Lower point and colour index for next row of ticks is here
    y = y + dy ;
    col = col + 1 ;
    
    % Too many sort codes? Circle back to first colour.
    if col > size( C.colord , 1 )
      col = size( C.colord , 1 ) ;
    end
    
  end % unique sc
  
end % chan

% New axes for cross-channel PSTH
ax = subplot( 3 , 1 , 3 , 'XLim' , [ -C.win.base , +C.win.resp ] , ...
  'NextPlot' , 'add' ) ;

% Labels
title( 'Cross-channel PSTH' )
xlabel( 'Time from trigger e.g. stimulus onset (s)' )
ylabel( 'Spike count' )

% All unique sort code values
USC = unique( D.bspk.mc )' ;

  % Keep non-zero ones
  USC( USC == 0 ) = [ ] ;

% Repeat time stamps for each channel
X = repmat( D.bspk.time , 1 , size( D.bspk.mc , 2 ) ) ;

% Sort code values
for  usc = USC
  
  % Bin all spikes
  histogram( X( D.bspk.mc == usc ) , -C.win.base : 0.05 : +C.win.resp )
  
end % sort codes

% Zero line
plot( [ 0 , 0 ], ax.YLim, 'Color', [ 0.6 , 0.6 , 0.6 ], 'LineWidth', 1 )

% Done
clearvars( '-except' , C.keep{ : } )


%% --- Done --- %%

% Release resources
DaqServer.Disconnect( ) ;
delete( C.syn )
clc , clearvars


%% --- Sub-routines --- %%

% Set scalar gizmo parameter, trigger error on failure
function  setpar( C , giz , par , val , err )
  
  if  ~ C.syn.setParameterValue( giz , par , val ) , error ( err ) , end
  
end % setpar

% Set array of gizmo parameter values, trigger error on failure. Assumes
% starting index of 0.
function  setpars( C , giz , par , val , err , off )

  % No offset given, use default
  if  nargin < 6 , off = 0 ; end
  
  if  ~ C.syn.setParameterValues( giz , par , val , off )
    error ( [ 'Failed to ' , err ] )
  end
  
end % setpars

% Read buffered data. giz is buffer gizmo struct. ind is final index
% at end of response window. buf names the buffer control to read from. siz
% is the total number of elements in the buffer, its size.
function  dat = readbuf( C , giz , ind , buf , siz )
  
  % Default value of dat
  dat = [ ] ;
  
  % No samples buffered. Return empty.
  if  giz.Counter == 0 , return , end
  
  % Number of buffered samples no more than size of buffer. Buffer has not
  % circled back to beginnig yet.
  if  giz.Counter <= giz.BuffSize
    
    % No action required
    
  % More samples buffered than buffer size. Buffer has looped back to
  % beginning at least once.
  elseif  giz.Counter > giz.BuffSize
    
    % Number of elements to read
    N = siz - ind ;
    
    % Read header
    dat = C.syn.getParameterValues( giz.nam , buf , N , ind ) ;
    
  % Shouldn't ever get here
  else , error( 'Programming error.' )
  end % buffer read pars
  
  % Number of elements to read
  N = ind ;
  
  % Read remainder of buffered data
  dat = [ dat ; C.syn.getParameterValues( giz.nam , buf , N , 0 ) ] ;
  
  % Cast to integer words if spike window buffer's MCsamples buffer
  if  strcmp( giz.nam , C.gizmo.bspk.nam )  &&  strcmp( buf , 'MCsamples' )
    dat = cast( dat , C.int.word ) ;
  end
  
end % readbuf

