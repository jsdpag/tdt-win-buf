
% 
% TdtWinBuf
% 
% Used to interface with custom Gizmos in a TDT Synapse experiment. These
% implement the windowed buffering of data. The intended workflow is that
% data is buffered during a trial, locally on the TDT system. After the
% trial, a TdtWinBuf object running on a remote system can be used to read
% the buffered data, for online analysis.
% 
% Multiple TdtWinBuf objects may be linked to the same windowed buffer
% Gizmo in the TDT system, in order to dynamically grab buffered data at
% multiple time points during a trial. Beware that there is some
% communication overhead that can affect timing of the trial.
% 
% Can only be created when Synapse is in run-time mode.
% 
% Written by Jackson Smith - March 2022 - Fries Lab (ESI Frankfurt)
% 

classdef  TdtWinBuf  <  handle
  
  
  %%% PROPERTIES %%%
  
  % Constants, TdtWinBuf read/write only.
  properties  ( Constant = true )
    
    % Required list of parameter names. Window buffer gizmo must return at
    % least this set. Note, in SynapseAPI, the term "parameter" seems to
    % refer to the Synapse Gizmo control, accessed in RFvdsEx with the
    % gizmoControl macro.
    REQPAR = { 'BuffSize' , 'ChanPerSamp' , 'DownSamp' , 'BitsPerVal' , ...
      'ScaleFactor' , 'CompDomain' , 'BuffSizeMC' , 'RespWin' , ...
        'StartBuff' , 'Mindex' , 'Sindex' , 'MCindex' , 'Counter' , ...
          'EventMin' , 'EventSec' , 'Minutes' , 'Seconds' , 'MCsamples' } ;
    
    % Bits per number (word, value, element) buffered on TDT system
    BITNUM = 32 ;
    
    % The reverse lookup table, take the domain code +1 as an index for
    % this cell array, to return the name of the compressed domain
    COMNAM = { 'none' , 'channels' , 'time' } ;

  end % constants
  
  
  % Don't save these properties if TdtWinBuf is stored to disk
  properties  ( Transient )
    
    % Instance of SynapseAPI object
    syn = [ ] ;
    
  end % transient prop
  
  
  % Only TdtWinBuf can read/write these properties. These contain
  % information about the Synapse custom Gizmo used to implement the
  % windowed buffer.
  properties  ( SetAccess = private )
    
    % Name of specific windowed buffer Gizmo, a specific instance, to be
    % read by this TdtWinBuf
    name = '' ;
    
    % Information about the Gizmo
    info = [ ] ;
    
    % Gizmo's parent device
    parent = '' ;
    
    % Cell array of char arrays, naming each Gizmo control, or parameter,
    % that is visible to SynapseAPI
    param = { } ;
    
    % Information about each parameter, this will be a struct. Each field
    % will be named after a parameter in .param, and contain information
    % about that parameter, as returned by SynapseAPI.
    ipar = [ ] ;
    
    % 'Seconds' per 'Minute'
    secpermin = [ ] ;
    
    % Parent device sampling rate. Buffered time stamps count the number of
    % samples at this rate.
    pfs = [ ] ;
    
    % Buffering sample rate. If samples are buffered once per N samples
    % and N > 1 then the buffer rate will be lower that the parent rate.
    bfs = [ ] ;
    
    % Cast buffered data into this type after reading. Empty string takes
    % default return value from SynapseAPI, which is double.
    readcast = 'double' ;
    
    % Typecast buffered data into new numeric type. Read in data as a
    % string of bits, and cast every contiguous block of bits into this
    % type. Ignored if empty. This is required to decompress spike sorter
    % Gizmo SortCodes.
    typcast = 'double' ;
    
    % Name of compression method used
    comnam = '' ;
    
    % Compression factor. Number of values stored per word e.g. 32-bit.
    comfac = [ ] ;
    
    % Buffer size, in number of compressed multi-channel samples
    cbsize = [ ] ;
    
    % Select a sub-set of channels. When compressing across channels, there
    % may be empty placeholders for channels above the actual channel
    % count. This property gives the actual channel count after de-
    % compressing the data.
    chsubsel = [ ] ;
    
    % Buffer size in seconds, rounded up to next multi-channel sample at
    % buffering rate
    bufsiz = [ ] ;
    
    % Response window duration in seconds, rounded up to next sample on
    % parent device clock
    respwin = [ ] ;
    
    % Time window, in seconds relative to start of buffer response window.
    % Any buffered samples that fall outside of this window are discarded.
    % This is inclusive. Time stamps that exactly equal a window edge will
    % be kept.
    timewin = [ -Inf , +Inf ]
    
    % Column vector of sample time stamps, in seconds
    time = [ ] ;
    
    % Samples x channels array of multi-channel samples
    data = [ ] ;
    
  end % private param
  
  
  %%% METHODS %%%
  
  % Functions that operate on a specific instance of a TdtWinBuf object
  methods
    
    %%-- Create an instance of TdtWinBuf object --%%
    
    % Create a new and unique instance of the TdtWinBuf class. Inputs are a
    % SynapseAPI object and a char array (string) naming the window buffer
    % Gizmo to be used by this TdtWinBuf.
    function  obj = TdtWinBuf( synapi , winbufgiz )
      
      %-- Error check input --%
      
      % synapi must be a SynapseAPI object
      if  ~ isa( synapi , 'SynapseAPI' )
        
        error( 'synapi must be a SynapseAPI object' )
        
      % Is Synapse in run-time mode?
      elseif  synapi.getMode( ) < 2
        
        error( 'Synapse must be in run-time mode' )
        
      % winbufgiz must be a string
      elseif  ~ ischar( winbufgiz )  ||  ~isrow( winbufgiz )
        
        error( 'winbufgiz must be a string i.e. char row vector' )
        
      end % check synapi class
      
      % Store SynapseAPI handle for future use
      obj.syn = synapi ;
      
      % Get list of visible Gizmos
      gnames = obj.syn.getGizmoNames( ) ;
      
      % Check that named win buf gizmo is visible
      if  ~ ismember( winbufgiz , gnames )
        
        error( 'SynapseAPI cannot find Gizmo called %s' , gnames )
        
      end % can't find winbufgiz
      
      % Store gizmo name
      obj.name = winbufgiz ;
      
      %-- Gizmo info --%
      
      % Specific information about the windowed buffer gizmo
      obj.info = obj.syn.getGizmoInfo( obj.name ) ;
      
      % Parent device of this gizmo
      obj.parent = obj.syn.getGizmoParent( obj.name ) ;
      
      % List of Gizmo's parameters i.e Gizmo controls
      obj.param = obj.syn.getParameterNames( obj.name ) ;
      
      % Check that all required parameters are visible
      if  ~ all(  ismember( obj.param , obj.REQPAR )  )
        
        error( 'Windowed buffer Gizmo %s must have parameters: %s' , ...
          obj.name , strjoin( obj.param , ' , ' ) )
        
      end % missing param
      
      % Initialise empty struct for parameter info
      obj.ipar = struct ;
      
      % Gizmo parameters
      for  P = obj.param' , p = P{ 1 } ;
        
        % Fetch more details about this parameter
        obj.ipar.( p ) = obj.syn.getParameterInfo( obj.name , p ) ;
        
        % Parameter is an array, skip to next parameter. The .Array
        % parameter will be the numeric array size, if it is an array.
        if  ~ strcmp( obj.ipar.( p ).Array , 'No' ) , continue , end
          
        % Get current value of parameter
        obj.ipar.( p ).Value = obj.syn.getParameterValue( obj.name, p ) ;
        
      end % params
      
      % Get Seconds per Minute
      obj.secpermin = obj.ipar.Seconds.Max ;
      
      %-- Derived information --%
      
      % Get sampling rates of TDT devices
      fs = obj.syn.getSamplingRates ;
      
      % Remember sampling rate of parent device
      obj.pfs = fs.( obj.parent ) ;
      
      % Sample buffering rate
      obj.bfs = obj.pfs  ./  obj.ipar.DownSamp.Value ;
      
      % Point to info about MCsamples parameter
      mcs = obj.ipar.MCsamples ;
      
      % Multi-channel buffer stores an integer data type
      if  strcmp( mcs.Type , 'Int' )
        
        % Build name of integer type. Buffered data will be cast to this
        % type after reading in.
        obj.readcast = sprintf( 'int%d' , obj.BITNUM ) ;
        
        % Unsigned integer
        if  mcs.Min >= 0 , obj.readcast = [ 'u' , obj.readcast ] ; end
        
      end % MCsamples casting
      
      % MC data compression signalled by Gizmo
      if  obj.ipar.CompDomain.Value
        
        % Each 32-bit word can be divided into consecutive groups bits
        % (BitsPerVal bits per group). Breat each 32-bit word into
        % consecutive values with this type, to decompress the data.
        obj.typcast = sprintf( 'int%d' , obj.ipar.BitsPerVal.Value ) ;
        
        % Unsigned integer
        if  mcs.Min >= 0 , obj.typcast = [ 'u' , obj.typcast ] ; end
        
      end % compression type
      
      % Uknown compression type
      if  obj.ipar.CompDomain.Value <  0  ||  ...
          obj.ipar.CompDomain.Value >= numel( obj.COMNAM )
      
        error( 'Uknown compression type in %s, code %d' , obj.name , ...
          obj.ipar.CompDomain.Value )
        
      % Known type of compression algorithm
      else
        
        % Fetch string naming this type of compression
        obj.comnam = obj.COMNAM{ obj.ipar.CompDomain.Value + 1 } ;
        
      end % compression type
      
      % Calculate number of compressed values per buffered value
      obj.comfac = obj.BITNUM  ./  obj.ipar.BitsPerVal.Value ;
      
      % Compute buffer size in number of compressed multi-channel samples,
      % according to compression type. Note, we assume sampling across the
      % time domain. Thus, only compression across the time domain will
      % change the actual buffer size from that reported in BuffSize.
      switch  obj.comnam
        
        % No compression. Or, compressed across channels domain.
        case { 'none' , 'channels' }, obj.cbsize = obj.ipar.BuffSize.Value;
          
        % Here, we worry. Each compressed and buffered MC sample contains
        % more than one sample in the time domain. The number of compressed
        % MC samples that can be buffered is derived from MC buffer size.
        case  'time' , obj.cbsize = obj.ipar.BuffSizeMC.Value  ./  ...
                                   obj.ipar.ChanPerSamp.Value ;
          
        % We should never get here
        otherwise
          
          error( 'Programming error, invalid compression type: %s' , ...
            obj.comnam )
          
      end % comp type
      
      % Initialise to largest possible number of channels
      obj.chsubsel = obj.maxchan ;
      
      % Determine size of buffer, in seconds. Divide number of
      % multi-channel samples by buffering rate. samples * seconds/sample.
      obj.bufsiz = obj.ipar.BuffSize.Value ./ obj.bfs ;
      
      % Again, find the duration of the response window, in seconds. Use
      % parent device samplind rate, this time.
      obj.respwin = obj.ipar.RespWin.Value ./ obj.pfs ;
      
      % Name buffer index parameter associated with each buffer parameter
        obj.ipar.Minutes.inam = 'Mindex' ;
        obj.ipar.Seconds.inam = 'Sindex' ;
      obj.ipar.MCsamples.inam = 'MCindex' ;
      
      % Set number of elements per buffered MC sample, per buffer parameter
        obj.ipar.Minutes.elpersamp = 1 ;
        obj.ipar.Seconds.elpersamp = 1 ;
      obj.ipar.MCsamples.elpersamp = obj.ipar.ChanPerSamp.Value ;
      
    end % TdtWinBuf
    
    
    %%-- Parameter setting --%%
    
    
    % Set channel sub-selection. Channels 1 to val are kept after reading.
    function  setchsubsel( obj , val )
      
      % Maximum channel count after decompression
      valmax = obj.maxchan ;
      
      % Value must be scalar integer
      if  ~ isnumeric( val ) || ~ isscalar( val ) || ~ isreal( val ) || ...
          ~ isfinite( val ) || mod( val , 1 ) ~= 0
        
        error( 'val must be scalar, finite, real-valued integer' )
        
      elseif  val < 1  ||  val > valmax
        
        error( 'val must be from range [1,%d]' , valmax )
        
      end % error check
      
      % Assign value
      obj.chsubsel = val ;
      
    end % setchsubsel
    
    
    % Set the size of the buffer, in seconds. Optional second argument
    % is the buffering rate; default uses obj.bfs. See checkfs for details.
    function  setbufsiz( obj , sec , fs )
      
      % Error check input, guarantee double
      sec = obj.checksec( sec ) ;
      
      % bfs not provided, use default
      if  nargin < 3
        fs = obj.bfs ;
      else
        fs = obj.checkfs( fs ) ; % Error check fs
      end
      
      % Compute buffer size in number of MC samples that it can store, with
      % or without compression. Round up to next sample.
      n = ceil( sec .* fs ) ;
      
      % Cap at maximum buffer size
      n = min( n , obj.ipar.BuffSize.Max ) ;
      
        % Convert this to seconds
        sec = n  ./  fs ;
      
      % Assign new buffer size to Gizmo
      obj.syn.setParameterValue( obj.name , 'BuffSize' , n ) ;
      
      % Read new buffer size
      obj.ipar.BuffSize.Value = obj.syn.getParameterValue( obj.name , ...
        'BuffSize' ) ;
      
        % Failed to write, warn user
        if  obj.ipar.BuffSize.Value ~= n
          warning( 'Failed to change %s BuffSize to %d' , obj.name , n )
        end
      
      % Fetch new multi-channel buffer size
      obj.ipar.BuffSizeMC.Value = obj.syn.getParameterValue( obj.name , ...
        'BuffSizeMC' ) ;
      
      % Compute from this what the buffer size is in number of compressed
      % samples
      obj.cbsize = obj.ipar.BuffSizeMC.Value  ./  ...
                  obj.ipar.ChanPerSamp.Value ;
      
      % Store buffer size, in seconds
      obj.bufsiz = sec ;
      
    end % setbufsiz
    
    
    % Set duration of response window, in seconds. Optional second argument
    % is the buffering rate; default uses obj.bfs. See checkfs for details.
    function  setrespwin( obj , sec , fs )
      
      % Error check input, guarantee double
      sec = obj.checksec( sec ) ;
      
      % bfs not provided, use default
      if  nargin < 3
        fs = obj.bfs ;
      else
        fs = obj.checkfs( fs ) ; % Error check fs
      end
      
      % Maximum response window that can be buffered
      maxwin = obj.ipar.BuffSize.Max ./ fs ;
      
      % Take the smaller value
      sec = min( sec , maxwin ) ;
      
      % Convert to number of samples on the parent device, round up to next
      % sample
      n = ceil( sec .* obj.pfs ) ;
      
        % Convert this value to seconds
        sec = n  ./  obj.pfs ;
      
      % Assign new response window to Gizmo
      obj.syn.setParameterValue( obj.name , 'RespWin' , n ) ;
      
      % Read back response window
      obj.ipar.RespWin.Value = obj.syn.getParameterValue( obj.name , ...
        'RespWin' ) ;
      
        % Failed to write new value, warn user
        if  obj.ipar.RespWin.Value ~= n
          warning( 'Failed to change %s RespWin to %d' , obj.name , n )
        end
      
      % Remember width of response window, in seconds
      obj.respwin = sec ;
      
    end % setrespwin
    
    
    % Set time window. Buffered data outside of this window are discarded.
    % Must be a 2 element numeric vector that is increasing. -Inf and +Inf
    % are valid values, and accept all data before or after the response
    % window.
    function  settimewin( obj , w )
      
      % Error check
      if  numel( w ) ~= 2 || ~ isnumeric( w ) || ~ isreal( w ) || ...
          any( isnan( w ) ) || w( 1 ) >= w( 2 )
        
        error( [ 'Input arg w must be 2 element, real-valued, ' , ...
          'non-NaN, numeric with w( 1 ) < w( 2 )' ] )
        
      end % error
      
      % For visualisation in call to disp, guarantee row vector
      obj.timewin = reshape( w , 1 , 2 ) ;
      
    end % settimewin
    
    
    %%-- Parameter setting utilities --%%
    
    
    % Error check input arg 'sec'. If it passes all tests then it is
    % returned, and guaranteed to be double.
    function  sec = checksec( ~ , sec )
      
      % Must be a numeric type, not cell, object, char, etc.
      if  ~isnumeric( sec ) || ~isscalar( sec ) || ~isfinite( sec ) || ...
            ~isreal( sec ) || sec < 0
        
        error( [ 'Input arg sec must be scalar, finite, real-valued' , ...
          'numeric value > 0' ] )
        
      end % error check
      
      % Is not double, cast value to double
      if  ~ isa( sec , 'double' ) , sec = double( sec ) ; end
      
    end % checksec
    
    
    % Error check input argument 'fs'. If it passes tests then it is
    % returned. If not type 'double' then it is first cast to double before
    % return. This argument is useful mainly when buffering spikes. In this
    % case, the maximum theoretical buffer rate equals the sampling rate of
    % the parent device e.g.~25kHz. But this might be much higher than the
    % maximum combined spiking rate across channels. The size of the
    % response window is limited by the size of the buffer and the
    % buffering rate. A smaller buffer could support a long response window
    % if the actual buffering rate (spiking rate) was much less than the
    % sampling rate of the parent device.
    function  fs = checkfs( obj , fs )
      
      % Error checking
      if  ~ isfloat( fs ) || ~ isscalar( fs ) || ~ isreal( fs ) || ...
          ~ isfinite( fs ) || fs <= 0 || fs > obj.pfs
      
        error( [ 'Input arg fs must be scalar, finite, real-valued, ' , ...
          'float in range (0,%.4f]Hz' ] , obj.pfs )
        
      end % err
      
      % Is not double, cast value to double
      if  ~ isa( fs , 'double' ) , fs = double( fs ) ; end
      
    end % checkfs
    
    
    % Maximum channel count after decompression
    function  m = maxchan( obj )
      
      % Largest possible numer of channels
      switch  obj.comnam
        
        % No compression or compressing across time
        case { 'none', 'time' } , m = obj.ipar.ChanPerSamp.Value ;
          
        % Compressing across channels
        case 'channels'
          
          % Initialise to largest possible number of channels
          m = obj.ipar.ChanPerSamp.Value * obj.comfac ;
          
      end % chsubsel
      
    end % maxchan
    
    
    %%-- Buffering operations --%%
    
    
    % Send a signal to the windowed buffer Gizmo to start or resume
    % circular buffering
    function  startbuff( obj )
      
      % Raise Gizmo's StartBuff parameter to high i.e. true, 1, ON
      obj.syn.setParameterValue( obj.name , 'StartBuff' , 1 ) ;
      
      % Immediately lower it again
      obj.syn.setParameterValue( obj.name , 'StartBuff' , 0 ) ;
      
    end % startbuff
    
    
    % Read in buffered data. We assume that the strobe event has been sent
    % to the windowed buffer Gizmo and that the full duration of the
    % response window has passed. Otherwise, incomplete and misaligned data
    % may be returned.
    function  getdata( obj )
      
      %-- Read buffers --%
      
      % Gizmo parameters, we need current value of these to successfully
      % read the buffers
      for  P = { 'Mindex' , 'Sindex' , 'MCindex' , 'Counter' , ...
          'EventMin' , 'EventSec' } , p = P{ 1 } ;
        
        % Read fresh value from Gizmo
        obj.ipar.( p ).Value = obj.syn.getParameterValue( obj.name , p ) ;
        
      end % read pars
      
      % Gizmo buffer parameters
      for  P = { 'Minutes' , 'Seconds' , 'MCsamples' } , p = P{ 1 } ;
        
        % Point to parameter info
        par = obj.ipar.( p ) ;
        
        % Read buffered data
        dat.( p ) = obj.read( par.inam , p , par.elpersamp ) ;
        
      end % buf pars
      
      %-- Time stamps --%
      
      % Converts from Gizmo 'Minutes' and 'Seconds' to the number of parent
      % device samples
      C = [ obj.secpermin ; 1 ] ;
      
      % Strobe event defines time zero for all buffered samples
      t0 = [ obj.ipar.EventMin.Value , obj.ipar.EventSec.Value ]  *  C ;
      
      % Sample times relative to time zero
      tim = [ dat.Minutes , dat.Seconds ] * C  -  t0 ;
      
      % Compression type
      switch  obj.comnam
        
        % Multiple samples over time were compressed into each buffered
        % multi-channel sample
        case  'time'
          
          % Number of parent device samples per buffered sample. This is
          % the period of each buffered sample.
          P = obj.ipar.DownSamp.Value ;
          
          % Number of samples compressed into each buffered sample
          N = obj.comfac ;
          
          % In this case, we must construct time stamps for compressed
          % samples. The time stamp we have is for the final compressed
          % sample. One buffered element contains [ s1 , s2 , ... sN ] when
          % N samples over time are compressed per buffered sample. If the
          % time of this buffered sample is tbuf then the time of sample si
          % is tbuf - (N - i)P, where P is the period of a buffered sample
          % (inverse buffering rate); take the unit of tbuf and P to be in
          % parent device samples. Note that binary singleton expansion
          % applies this operation to each element of column vector tim,
          % returning a matrix with rows ordered by buffered samples, and
          % columns ordered by compressed samples.
          tim = tim  -  ( N - 1 : -1 : 0 ) .* P ;
          
          % Use column major indexing to return times of each un-compressed
          % sample, in chronological order
          tim = reshape( tim' , numel( tim ) , 1 ) ;
          
      end % comp type
      
      % Convert unit from samples to seconds. It's worth mentioning here
      % that all time stamps are relative to the parent device clock. This
      % is why the parent sampling rate is used to change units.
      tim = tim ./ obj.pfs ;
      
      %-- Multi-channel samples --%
      
      % SynapseAPI returns double floating point values. Cast the numerical
      % values into an appropriate numerical type, as indicated by
      % properties of the Gizmo buffer parameter.
      if  ~ strcmp( obj.readcast , 'double' )
        dat.MCsamples = cast( dat.MCsamples , obj.readcast ) ;
      end
      
      % If values were compressed into single MC buffer elements, then we
      % break these appart into separate values through typecasting
      if  ~ strcmp( obj.comnam , 'none' )
        dat.MCsamples = typecast( dat.MCsamples , obj.typcast ) ;
      end
      
      % Point to number of channels
      N = obj.ipar.ChanPerSamp.Value ;
      
      % Compression type. After this, N will have number of channels.
      switch  obj.comnam
        
        % Data compressed across channels
        case  'channels'
          
          % Determine total number of channels. ChanPerSamp is the channel
          % count of each buffered sample, or the number of elements per
          % sample. Each element contains comfac compressed values. The
          % total number of values per buffered sample is ChanPerSamp x
          % comfac. For channel compression, this also equals the total
          % number of channels, prior to compression.
          N = N  *  obj.comfac ;
        
        % Data compressed across time. Here we need to be careful. There is
        % a nested order to the column vector in dat.MCsamples. Compressed
        % samples are ordered within blocks, each block is ordered by
        % channel. Blocks of channels iterate across all buffered samples.
        case  'time'
          
          % Re-arrange the data so that rows are ordered by compressed
          % samples, columns by channel, and dim 3 by buffered samples
          dat.MCsamples = reshape( dat.MCsamples , obj.comfac , N , [ ] ) ;
          
          % Permute the array such that channels are ordered across rows,
          % compressed samples across columns, and buffered samples stay in
          % dim 3
          dat.MCsamples = permute( dat.MCsamples , [ 2 , 1 , 3 ] ) ;
        
      end % comp type
      
      % Re-order the data into a samples x channels matrix
      dat.MCsamples = reshape( dat.MCsamples , N , [ ] )' ;
      
      % Check that number of time stamps equals the number of samples
      if  numel( tim ) ~= size( dat.MCsamples , 1 )
        error( 'Time-stamp to sample mismatch' )
      end
      
      % Channel sub-selection is requested, discard un-wanted channels
      if  obj.chsubsel < obj.maxchan
        dat.MCsamples( : , obj.chsubsel + 1 : end ) = [ ] ;
      end
      
      % If a scaling factor was applied, then we must remove it. This
      % requires casting to double.
      if  obj.ipar.ScaleFactor.Value ~= 1
        
        dat.MCsamples = double( dat.MCsamples )  ./  ...
          obj.ipar.ScaleFactor.Value ;
        
      end % scaling
      
      % A time window was provided, to crop away unwanted samples that lie
      % outside
      if  ~ all( isinf( obj.timewin ) )
        
        % Find data outside of time window
        i = tim < obj.timewin( 1 ) | obj.timewin( 2 ) < tim ;
        
        % Discard data
        tim( i ) = [ ] ;
        dat.MCsamples( i , : ) = [ ] ;
        
      end % discard data outside of time window
      
      % Store results
      obj.time = tim ;
      obj.data = dat.MCsamples ;
      
    end % getdata
    
    
    % Read and return buffered data. Provide name of index parameter and
    % buffer in inam and bnam. elpersamp is the number of words (e.g.
    % 32-bit float or int) buffered per sample; that is, the number of
    % buffer elements consumed per multi-channel sample. For time-stamp
    % buffers, elpersamp is 1. For multi-channel buffers, this is the
    % ChanPerSamp parameter value.
    function  dat = read( obj , inam , bnam , elpersamp )
      
      % Default return value
      dat = [ ] ;
      
      % Number of multi-channel samples that were buffered
      c = obj.ipar.Counter.Value ;
      
      % No buffered data, return empty
      if  c == 0 , return , end
        
      % Buffer's index value, in buffer elements
      i = obj.ipar.( inam ).Value ;
        
      % Number of buffered samples exceeds the capacity of the buffers. The
      % circular buffers have looped. We need to read the tail end of the
      % buffer in order to get the head of the data. 
      %   buffer = [ data tail , data head ]
      if  c > obj.cbsize
        
        % Number of elements in buffer tail. Find by subtracting index from
        % total number of elements in the buffer.
        n = elpersamp .* obj.cbsize  -  i ;
        
        % Read in head of the data
        dat = obj.syn.getParameterValues( obj.name , bnam , n , i ) ;
        
      end % fetch header
      
      % Number of elements to read from head of buffer i.e. tail of data if
      % buffers have looped
      n = i ;
      
      % Read tail of data (if looped) or entire set of buffered data, head
      % to tail (no loop)
      dat = [ dat ;
              obj.syn.getParameterValues( obj.name , bnam , n , 0 ) ] ;
      
    end % read
    
    
  end % methods
  
end % TdtWinBuf class definition

