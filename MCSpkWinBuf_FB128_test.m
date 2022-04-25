
% 
% MCSpkWinBuf_FB128_test.m
% 
% For use with Synapse experiment Test_FB128_WinBuf. Controls firing rate
% of FB128 simulated neurones via DAQ -> RZ2 TTL pulse. Duration of pulse
% controls tuning of neurones for an arbitrary stimulus parameter. Tuning
% curves have a Gaussian shape.
% 

%% -- CONSTANTS -- %%

% Network name of system upon which Synapse is running
C.server = 'ESI-WSFRI026' ;

% Names of windowed buffer gizmos
C.buf.spk = 'MCSpkWinBuf1'  ;
C.buf.mua = 'MCaMUAWinBuf1' ;
C.buf.lfp = 'MCLfpWinBuf1'  ;

% Gather in cell array
C.bufnam = { C.buf.spk , C.buf.mua , C.buf.lfp } ;

% Tuning curve function. Inputs - x: stimulus parameter value(s), dur:
% maximum duration of response to stimulus in milliseconds, mu: preferred
% stimulus value, sig: width of tuning curve.
C.tun.fun = ...
  @( x, dur, mu, sig ) dur .* exp( -( x - mu ) .^ 2 ./ ( 2 .* sig .^ 2 ) );

% Tuning curve properties { dur , mu , sig }
C.tun.prop = { 1e3 , 0 , 1 } ;

% Stimulus values to test
C.stim = -3.5 : 0.5 : +3.5 ;

% Latency of neuronal response, in milliseconds
C.lat = 30 ;

% Time window, baseline and response
C.win = [ -500 , C.tun.prop{ 1 } ] ;

% But in practice we need a bit off wiggle room at the ends in order to
% deal with the irregular sampling rate of TDT hardware
C.rawwin = [ -5 , +5 ] + C.win ;

% Response window for online analysis
C.reswin = [ 30 , C.tun.prop{ 1 } ] ;

% millisecond bins, plus one for last, right-most bin edge
C.bin = C.win( 1 ) : C.win( 2 ) + 1 ;

% Spk raster convolution kernel
C.kern = ones( 10 , 1 ) ./ 10 ;

% Variables to keep
C.keep = { 'C' } ;


%% -- Add MAK to path -- %%

% We need this for rapid, FFT based convolution. Add to path.
addpath C:\Users\smithj\Documents\MATLAB\mak\


%% -- Connect to SynapseAPI -- %%

% SynapseAPI not opened yet, or it was closed. If it is open then don't
% bother implicitly destroying existing SynapseAPI object just to make a
% new one.
if  ~ isfield( C , 'syn' )  ||  ~ isvalid( C.syn )
  C.syn = SynapseAPI( C.server ) ;
end

% Guarantee that run-time mode is active
if  C.syn.getMode < 2
  error( 'Synapse must be in run-time mode.' )
end

% Gizmos names
nam = C.syn.getGizmoNames ;

% Look for our Gizmos
i = ismember( C.bufnam , nam ) ;

  % Something's missing, tell user
  if  ~ all( i )
    
    error( 'Synapse session lacks Gizmo(s): %s' , ...
      strjoin( C.bufnam( ~i ) , ' , ' ) )
    
  end % missing giz

% Buffer field names
for  F = fieldnames( C.buf )' , f = F{ 1 } ;
  
  % Create instance of TdtWinBuf class in order to communicate with this
  % specific buffer
  C.tdt.( f ) = TdtWinBuf( C.syn , C.buf.( f ) ) ;
  
  % Make sure that response window is long enough
  C.tdt.( f ).setrespwin( C.rawwin( 2 ) ./ 1e3 )
  
  % Return only data points within this time range
  C.tdt.( f ).settimewin( C.rawwin ) ;
  
end % giz

% Make sure that spike buffer object returns appropriate sub-set of
% channels
C.tdt.spk.setchsubsel( C.tdt.lfp.chsubsel ) ;

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


%% Create figures

% Screen size
scr = get( groot , 'ScreenSize' ) ;

% Buffer field names
for  F = fieldnames( C.buf )' , f = F{ 1 } ;
  
  % Look for this figure
  h = findobj( 'Type' , 'figure' , 'Tag' , f ) ;
  
  % Does not exist , create
  if  isempty( h )
    
    h = figure ;
    
    % Increase height and width, a bit
    h.Position( 3 : 4 ) = [ 1.5 , 2 ] .* h.Position( 3 : 4 ) ;
    
    % Guarantee that figure top banner is visible
    h.OuterPosition( 2 ) = scr( 4 ) - h.OuterPosition( 4 ) ;
    
    % Set figure title
    h.Name = f ;
    
    % Callback grabs <Enter>. True when not q. False when q. See trials
    % loop.
    h.KeyPressFcn = ...
      @( f , k ) set( f , 'UserData' , ~ strcmp( k.Key , 'q' ) ) ;
    
  end % new fig
  
  % Axes index
  i = 0 ;
  
  % Channels, next axes
  for  row = 1 : C.tdt.( f ).chsubsel
    
    % Axes columns
    for  col = 1 : 2 , i = i + 1 ;

      % Type of plot and size of errorbar internal data. X-axis data will
      % never change so set it here.
      switch  col
        case 1 , typ = 'psth' ; x = C.bin( 1 : end - 1 ) ;
        case 2 , typ = 'tune' ; x = C.stim ;
      end
      
      % Number of points on x-axis
      siz = size( x ) ;
      
      % New axes, or retrieve existing
      ax = subplot( C.tdt.( f ).chsubsel , 2 , i ) ;
      
      % Guarantee hold is off before object creation
      hold off
      
      % Initialise new error bar
      y = nan( siz ) ; e = nan( siz ) ;
      
      % Create new error bar
      errorbar( x , y , e , 'k' )
      
      % Formatting
      ax.Tag = sprintf( 'ch%d_%s' , row , typ ) ;
      axis tight
      xlim( x( [ 1 , end ] ) )
      grid on
      
      % Title on first row
      if  row == 1 , title( typ ) , end
      
    end % row
  end % col
  
end % buf fields

% Done
clearvars( '-except' , C.keep{ : } )


%% --- Run Simulation --- %%

%-- Initialisation --%

% Fresh Welford array, dimensions: [ N samples , N channels , data types ]
W.psth = Welford( numel( C.bin  ) - 1 , C.tdt.spk.chsubsel , 3 ) ;
W.tune = Welford( numel( C.stim )     , C.tdt.spk.chsubsel , 3 ) ;

% Dim 3 index
w3 = struct( 'spk' , 1 , 'mua' , 2 , 'lfp' , 3 ) ;

% Figures, reset UserData to scalar true i.e. continue trials loop.
for  h = findobj( 'Type' , 'figure' )' , h.UserData = true ; end

% Error bar objects
for  h = findobj( 'Type' , 'errorbar' )'
  
  % Reset
  h.YData( : ) = NaN ;
  h.YNegativeDelta( : ) = NaN ;
  h.YPositiveDelta( : ) = NaN ;
  
end % err bars

% Update plots
drawnow

% Point to first figure
h = findobj( 'Type' , 'figure' , 'Name' , 'spk' ) ;

% Clear command window
clc

%-- Simulation --%

% Trial counter
N = 0 ;

% Trials loop, count trials
while  h.UserData , N = N + 1 ;
  
  % Randomly sample a stimulus value, return its index
  s = ceil( numel( C.stim ) * rand ) ;
  
  % Compute duration of neuronal response to stimulus onset, round up to
  % next millisecond. Includes latency.
  t = ceil( C.tun.fun( C.stim( s ) , C.tun.prop{ : } ) )  +  C.lat ;
  
  % Resume data buffering in each TDT windowed buffer
  for  F = fieldnames( C.buf )' , f = F{ 1 } ; C.tdt.( f ).startbuff ; end
  
  % Report
  fprintf( '\nTrial %d, stim %f\nBaseline %dms\n' , ...
    N , C.stim( s ) , abs( C.win( 1 ) ) )
  
  % Wait for baseline
  sleep( abs( C.rawwin( 1 ) ) )
  
  % Report next step
  fprintf( 'Stimulus on for %dms\n' , C.win( 2 ) )
  
  % Present stimulus
  DaqServer.EventMarker( 1 ) ;  sleep( t ) ;  DaqServer.EventMarker( 0 ) ;
  
  % Wait for remainder of trial
  sleep( max( C.rawwin( 2 ) - t , 0 ) )
  
  % Report stimulus event and next buffer operation
  fprintf( 'Stimulus off\nRetrieve buffered data\n' )
  
  % Retrieve buffered data
  tic
  for  F = fieldnames( C.buf )' , f = F{ 1 } ; C.tdt.( f ).getdata ; end
  
  % Report time taken
  fprintf( '  Operation took %f seconds\n' , toc )
  
  % Buffers
  for  F = fieldnames( C.buf )' , f = F{ 1 } ;

    % Buffered data, time in milisseconds
    tim = C.tdt.( f ).time .* 1e3 ;
    dat = C.tdt.( f ).data ;
    
    % If spk then replace any non-zero data with ones
    switch  f , case 'spk' , dat( dat > 0 ) = 1 ; end
    
    % Find time bins within response analysis window
    i = C.reswin( 1 ) <= tim & tim <= C.reswin( 2 ) ;
    
    % Compute mean response per second
    switch  f
      
      % Sum spikes over window, divide by number of seconds
      case  'spk' , X = sum( dat( i , : ) , 1 ) ./ diff( C.reswin ) .* 1e3;
        
      % Average continuous data over samples, convert denom from samp to s
      % using buffering sample rate.
      otherwise , X = mean( dat( i , : ) , 1 ) .* C.tdt.( f ).bfs ;
        
    end % resp per sec
    
    % Add data to Welford array
    W.tune( s , : , w3.( f ) ) = W.tune( s , : , w3.( f ) )  +  X ;
    
    % Get millisecond-binned data
    switch  f
      
      % Spike data
      case  'spk'
        
        % Convert data to logical
        dat = logical( dat ) ;
        
        % Bin separately for each channel
        X = arrayfun( ...
          @( ch ) histcounts( tim( dat( : , ch ) ) , C.bin )' , ...
            1 : C.tdt.( f ).chsubsel , 'UniformOutput' , false ) ;
        
        % Collapse into numeric array
        X = [ X{ : } ] ;
        
        % Convolve spike trains
        X = makconv( X , C.kern , 's' ) ;
        
      % Continuous data, linear interpolation
      otherwise , X = interp1( tim , dat , C.bin( 1 : end - 1 ) ) ;
        
    end % ms bin
    
    % Accumulate time series data
    W.psth( : , : , w3.( f ) ) = W.psth( : , : , w3.( f ) )  +  X ;
    
    % Find associated figure
    h = findobj( 'Type' , 'figure' , 'Name' , f ) ;
    
    % Channels
    for  row = 1 : C.tdt.( f ).chsubsel
      
      % Data types
      for  TYP = fieldnames( W )' , typ = TYP{ 1 } ;
        
        % Find axes
        ax = findobj( h , 'Tag' , sprintf( 'ch%d_%s' , row , typ ) ) ;
        
        % And now find errorbar object
        e = findobj( ax , 'Type' , 'errorbar' ) ;
        
        % Update data from Welford array
        e.YData( : ) = W.( typ ).avg( : , row , w3.( f ) ) ;
        e.YNegativeDelta( : ) = W.( typ )( : , row , w3.( f ) ).sem ;
        e.YPositiveDelta( : ) = e.YNegativeDelta ;
        
      end % types
    end % chan
    
  end % buf
  
  % Point to all figures
  h = cellfun( @( f ) findobj( 'Type' , 'figure' , 'Name' , f ) , ...
    fieldnames( C.buf ) ) ;
  
  % Return figure userdata, which records whether or not 'q' has been typed
  x = get( h , 'UserData' ) ;
  
  % Test whether all are true, store result in UserData of first figure in
  % list
  h( 1 ).UserData = all( [ x{ : } ] ) ;
  
  % Point to only the first figure in list. h.UserData controls loop.
  h( 2 : end ) = [ ] ;
  
  % Update figures
  drawnow
  
end % trial loop

% Report
fprintf( 'Quit simulation\n' )

% Done
clearvars( '-except' , C.keep{ : } )


%% --- Done --- %%

% Release resources
DaqServer.Disconnect( ) ;
delete( C.syn )
clc , clearvars
