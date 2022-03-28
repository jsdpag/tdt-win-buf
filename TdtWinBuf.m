
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
    REQPAR = { 'BuffSize' , 'ChanPerSamp' , 'DownSamp' , 'BuffSizeMC' , ...
      'RespWin' , 'StartBuff' , 'Mindex' , 'Sindex' , 'MCindex' , ...
        'Counter' , 'EventMin' , 'EventSec' , 'Minutes' , 'Seconds' , ...
          'MCsamples' }
    
    % Bits per number (word, value, element) buffered on TDT system
    BITNUM = 32 ;

  end % constants
  
  % Only TdtWinBuf can read/write these properties. These contain
  % information about the Synapse custom Gizmo used to implement the
  % windowed buffer.
  properties  ( SetAccess = private )
    
    % Name of specific windowed buffer Gizmo, a specific instance, to be
    % read by this TdtWinBuf
    gname = '' ;
    
    % Information about the Gizmo
    ginfo = [ ] ;
    
    % Gizmo's parent device
    gparent = '' ;
    
    % Cell array of char arrays, naming each Gizmo control, or parameter,
    % that is visible to SynapseAPI
    param = { } ;
    
    % Information about each parameter, this will be a struct. Each field
    % will be named after a parameter in .param, and contain information
    % about that parameter, as returned by SynapseAPI.
    pinfo = [ ] ;
    
    % Parent device sampling rate. Buffered time stamps count the number of
    % samples at this rate.
    pfs = [ ] ;
    
    % Buffering sample rate. If samples are buffered once per N samples
    % and N > 1 then the buffer rate will be lower that the parent rate.
    bfs = [ ] ;
    
    % Cast buffered data into this type after reading. Empty string takes
    % default return value from SynapseAPI, which is double.
    rcast = '' ;
    
    % Typecast buffered data into new numeric type. Read in data as a
    % string of bits, and cast every contiguous block of bits into this
    % type. Ignored if empty. This is required to decompress spike sorter
    % Gizmo SortCodes.
    tcast = '' ;
    
    % Buffer size in seconds, rounded up to next multi-channel sample at
    % buffering rate
    bufsiz = [ ] ;
    
    % Response window duration in seconds, rounded up to next sample on
    % parent device clock
    respwin = [ ] ;
    
    % Column vector of sample time stamps, in seconds
    time = [ ] ;
    
    % Samples x channels array of multi-channel samples
    data = [ ] ;
    
  end % private param
  
  % Don't save these properties if TdtWinBuf is stored to disk
  properties  ( Transient )
    
    % Instance of SynapseAPI object
    syn
    
  end % transient prop
  
  
  %%% METHODS %%%
  
  % Functions that operate on a specific instance of a TdtWinBuf object
  methods
    
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
      obj.gname = winbufgiz ;
      
      %-- Gizmo info --%
      
      % Specific information about the windowed buffer gizmo
      obj.ginfo = obj.syn.getGizmoInfo( obj.gname ) ;
      
      % Parent device of this gizmo
      obj.gparent = obj.syn.getGizmoParent( obj.gname ) ;
      
      % List of Gizmo's properties
      obj.param = obj.syn.getParameterNames( obj.gname ) ;
      
      % Check that all required parameters are visible
      if  ~ all(  ismember( obj.param , obj.REQPAR )  )
        
        error( 'Windowed buffer Gizmo %s must have parameters: %s' , ...
          obj.gname , strjoin( obj.param , ' , ' ) )
        
      end % missing param
      
      % Initialise empty struct for parameter info
      obj.pinfo = struct ;
      
      % Gizmo parameters
      for  P = obj.param' , p = P{ 1 } ;
        
        % Fetch more details about this parameter
        obj.pinfo.( p ) = obj.syn.getParameterInfo( obj.gname , p ) ;
        
        % Parameter is an array, skip to next parameter. The .Array
        % parameter will be array size if it is an array.
        if  ~ strcmp( obj.pinfo.( p ).Array , 'No' ) , continue , end
          
        % Get current value of parameter
        obj.pinfo.( p ).Value = obj.syn.getParameterValue( obj.gname, p ) ;
        
      end % params
      
      % Get sampling rates of TDT devices
      fs = obj.syn.getSamplingRates ;
      
      % Remember sampling rate of parent device
      obj.pfs = fs.( obj.gparent ) ;
      
      % Sample buffering rate
      obj.bfs = obj.pfs  ./  obj.pinfo.DownSamp.Value ;
      
      % Point to info about MCsamples parameter
      mcs = obj.pinfo.MCsamples ;
      
      % Buffers integer data type
      if  strcmp( mcs.Type , 'Int' )
        
        % Build name of integer type. Buffered data will be cast to this
        % type after reading in.
        obj.rcast = sprintf( 'int%d' , obj.BITNUM ) ;
        
        % Unsigned integer
        if  mcs.Min >= 0 , obj.rcast = [ 'u' , obj.rcast ] ; end
        
      end % MCsamples casting
      
      % Determine size of buffer, in seconds. Divide number of
      % multi-channel samples by buffering rate. samples * seconds/sample.
      obj.bufsiz = obj.pinfo.BuffSize.Value ./ obj.bfs ;
      
      % Again, find the duration of the response window, in seconds. Use
      % parent device samplind rate, this time.
      obj.respwin = obj.pinfo.RespWin.Value ./ obj.pfs ;
      
    end % TdtWinBuf
    
    
    % Send a signal to the windowed buffer Gizmo to start or resume
    % circular buffering
    function  startbuff( obj )
      
      % Raise Gizmo's StartBuff parameter to high i.e. true, 1, ON
      obj.syn.setParameterValue( obj.gname , 'StartBuff' , 1 ) ;
      
      % Immediately lower it again
      obj.syn.setParameterValue( obj.gname , 'StartBuff' , 0 ) ;
      
    end % startbuff
    
    
    % Tell TdtWinBuf whether buffered data are SortCodes. Input is True or
    % False. If True, then type-casting integer type is set appropriately.
    % If False then no type-casting is used.
    function  sortcodes( obj , sc )
      
      % Buffered data contains SortCodes
      if  sc
        
        % Successive ephys channel encoded by successive bytes
        obj.tcast = 'uint8' ;
        
      % Buffered data does not contain SortCodes
      else
        
        % No typecasting
        obj.tcast = '' ;
        
      end % switch on/off typecasting
      
    end % SortCodes
    
    
  end % methods
  
end % TdtWinBuf class definition

